# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['AlertManagementStatus'] do
  specify { expect(described_class.graphql_name).to eq('AlertManagementStatus') }

  describe 'statuses' do
    using RSpec::Parameterized::TableSyntax

    where(:status_name, :status_value) do
      'TRIGGERED'    | 0
      'ACKNOWLEDGED' | 1
      'RESOLVED'     | 2
      'IGNORED'      | 3
    end

    with_them do
      it 'exposes a status with the correct value' do
        expect(described_class.values[status_name].value).to eq(status_value)
      end
    end
  end
end
