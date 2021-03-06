# frozen_string_literal: true

module Groups
  class TransferService < Groups::BaseService
    TransferError = Class.new(StandardError)

    attr_reader :error, :new_parent_group

    def initialize(group, user, params = {})
      super
      @error = nil
    end

    def execute(new_parent_group)
      @new_parent_group = new_parent_group
      ensure_allowed_transfer
      proceed_to_transfer

    rescue TransferError, ActiveRecord::RecordInvalid, Gitlab::UpdatePathError => e
      @group.errors.clear
      @error = s_("TransferGroup|Transfer failed: %{error_message}") % { error_message: e.message }
      false
    end

    private

    def proceed_to_transfer
      Group.transaction do
        update_group_attributes
        ensure_ownership
      end

      post_update_hooks(@updated_project_ids)

      true
    end

    # Overridden in EE
    def post_update_hooks(updated_project_ids)
    end

    def ensure_allowed_transfer
      raise_transfer_error(:group_is_already_root) if group_is_already_root?
      raise_transfer_error(:same_parent_as_current) if same_parent?
      raise_transfer_error(:invalid_policies) unless valid_policies?
      raise_transfer_error(:namespace_with_same_path) if namespace_with_same_path?
      raise_transfer_error(:group_contains_images) if group_projects_contain_registry_images?
      raise_transfer_error(:cannot_transfer_to_subgroup) if transfer_to_subgroup?
      raise_transfer_error(:group_contains_npm_packages) if group_with_npm_packages?
    end

    def group_with_npm_packages?
      return false unless group.packages_feature_enabled?

      npm_packages = ::Packages::GroupPackagesFinder.new(current_user, group, package_type: :npm).execute

      return true if different_root_ancestor? && npm_packages.exists?

      false
    end

    def different_root_ancestor?
      group.root_ancestor != new_parent_group&.root_ancestor
    end

    def group_is_already_root?
      !@new_parent_group && !@group.has_parent?
    end

    def same_parent?
      @new_parent_group && @new_parent_group.id == @group.parent_id
    end

    def transfer_to_subgroup?
      @new_parent_group && \
      @group.self_and_descendants.pluck_primary_key.include?(@new_parent_group.id)
    end

    def valid_policies?
      return false unless can?(current_user, :admin_group, @group)

      if @new_parent_group
        can?(current_user, :create_subgroup, @new_parent_group)
      else
        can?(current_user, :create_group)
      end
    end

    # rubocop: disable CodeReuse/ActiveRecord
    def namespace_with_same_path?
      Namespace.exists?(path: @group.path, parent: @new_parent_group)
    end
    # rubocop: enable CodeReuse/ActiveRecord

    def group_projects_contain_registry_images?
      @group.has_container_repository_including_subgroups?
    end

    def update_group_attributes
      if @new_parent_group && @new_parent_group.visibility_level < @group.visibility_level
        update_children_and_projects_visibility
        @group.visibility_level = @new_parent_group.visibility_level
      end

      @group.parent = @new_parent_group
      @group.clear_memoization(:self_and_ancestors_ids)
      @group.save!
    end

    # rubocop: disable CodeReuse/ActiveRecord
    def update_children_and_projects_visibility
      descendants = @group.descendants.where("visibility_level > ?", @new_parent_group.visibility_level)

      Group
        .where(id: descendants.select(:id))
        .update_all(visibility_level: @new_parent_group.visibility_level)

      projects_to_update = @group
        .all_projects
        .where("visibility_level > ?", @new_parent_group.visibility_level)

      # Used in post_update_hooks in EE. Must use pluck (and not select)
      # here as after we perform the update below we won't be able to find
      # these records again.
      @updated_project_ids = projects_to_update.pluck(:id)

      projects_to_update
        .update_all(visibility_level: @new_parent_group.visibility_level)
    end
    # rubocop: enable CodeReuse/ActiveRecord

    def ensure_ownership
      return if @new_parent_group
      return unless @group.owners.empty?

      @group.add_owner(current_user)
    end

    def raise_transfer_error(message)
      raise TransferError, localized_error_messages[message]
    end

    def localized_error_messages
      {
        database_not_supported: s_('TransferGroup|Database is not supported.'),
        namespace_with_same_path: s_('TransferGroup|The parent group already has a subgroup with the same path.'),
        group_is_already_root: s_('TransferGroup|Group is already a root group.'),
        same_parent_as_current: s_('TransferGroup|Group is already associated to the parent group.'),
        invalid_policies: s_("TransferGroup|You don't have enough permissions."),
        group_contains_images: s_('TransferGroup|Cannot update the path because there are projects under this group that contain Docker images in their Container Registry. Please remove the images from your projects first and try again.'),
        cannot_transfer_to_subgroup: s_('TransferGroup|Cannot transfer group to one of its subgroup.'),
        group_contains_npm_packages: s_('TransferGroup|Group contains projects with NPM packages.')
      }.freeze
    end
  end
end

Groups::TransferService.prepend_if_ee('EE::Groups::TransferService')
