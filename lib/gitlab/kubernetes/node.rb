# frozen_string_literal: true

module Gitlab
  module Kubernetes
    class Node
      def initialize(cluster)
        @cluster = cluster
      end

      def all
        nodes.map do |node|
          attributes = node(node)
          attributes.merge(node_metrics(node))
        end
      end

      private

      attr_reader :cluster

      def nodes_from_cluster
        graceful_request { cluster.kubeclient.get_nodes }
      end

      def nodes_metrics_from_cluster
        graceful_request { cluster.kubeclient.metrics_client.get_nodes }
      end

      def nodes
        @nodes ||= nodes_from_cluster[:response].to_a
      end

      def nodes_metrics
        @nodes_metrics ||= nodes_metrics_from_cluster[:response].to_a
      end

      def node_metrics_from_node(node)
        nodes_metrics.find do |node_metric|
          node_metric.metadata.name == node.metadata.name
        end
      end

      def graceful_request(&block)
        ::Gitlab::Kubernetes::KubeClient.graceful_request(cluster.id, &block)
      end

      def node(node)
        {
          'metadata' => {
            'name' => node.metadata.name
          },
          'status' => {
            'capacity' => {
              'cpu' => node.status.capacity.cpu,
              'memory' => node.status.capacity.memory
            },
            'allocatable' => {
              'cpu' => node.status.allocatable.cpu,
              'memory' => node.status.allocatable.memory
            }
          }
        }
      end

      def node_metrics(node)
        node_metrics = node_metrics_from_node(node)
        return {} unless node_metrics

        {
          'usage' => {
            'cpu' => node_metrics.usage.cpu,
            'memory' => node_metrics.usage.memory
          }
        }
      end
    end
  end
end
