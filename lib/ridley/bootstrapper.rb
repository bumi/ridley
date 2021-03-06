module Ridley
  # @author Jamie Winsor <jamie@vialstudios.com>
  class Bootstrapper
    autoload :Context, 'ridley/bootstrapper/context'

    class << self
      # @return [Pathname]
      def templates_path
        Ridley.root.join('bootstrappers')
      end

      # @return [String]
      def default_template
        templates_path.join('omnibus.erb').to_s
      end
    end

    include Celluloid
    include Celluloid::Logger

    # @return [Array<String>]
    attr_reader :hosts

    # @return [Array<Bootstrapper::Context>]
    attr_reader :contexts

    # @return [Hash]
    attr_reader :ssh_config

    # @param [Array<#to_s>] hosts
    # @option options [String] :ssh_user
    # @option options [String] :ssh_password
    # @option options [Array<String>, String] :ssh_keys
    # @option options [Float] :ssh_timeout
    #   timeout value for SSH bootstrap (default: 1.5)
    # @option options [String] :validator_client
    # @option options [String] :validator_path
    #   filepath to the validator used to bootstrap the node (required)
    # @option options [String] :bootstrap_proxy
    #   URL to a proxy server to bootstrap through (default: nil)
    # @option options [String] :encrypted_data_bag_secret_path
    #   filepath on your host machine to your organizations encrypted data bag secret (default: nil)
    # @option options [Hash] :hints
    #   a hash of Ohai hints to place on the bootstrapped node (default: Hash.new)
    # @option options [Hash] :attributes
    #   a hash of attributes to use in the first Chef run (default: Hash.new)
    # @option options [Array] :run_list
    #   an initial run list to bootstrap with (default: Array.new)
    # @option options [String] :chef_version
    #   version of Chef to install on the node (default: {Ridley::CHEF_VERSION})
    # @option options [String] :environment
    #   environment to join the node to (default: '_default')
    # @option options [Boolean] :sudo
    #   bootstrap with sudo (default: true)
    # @option options [String] :template
    #   bootstrap template to use (default: omnibus)
    def initialize(hosts, options = {})
      @hosts      = Array(hosts).collect(&:to_s).uniq
      @ssh_config = {
        user: options.fetch(:ssh_user),
        password: options[:ssh_password],
        keys: options[:ssh_keys],
        timeout: (options[:ssh_timeout] || 1.5)
      }

      @contexts = @hosts.collect do |host|
        Context.new(host, options)
      end
    end

    # @return [SSH::ResponseSet]
    def run
      if contexts.length >= 2
        pool = SSH::Worker.pool(size: contexts.length, args: [self.ssh_config])
      else
        pool = SSH::Worker.new(self.ssh_config)
      end

      responses = contexts.collect do |context|
        pool.future.run(context.host, context.boot_command)
      end.collect(&:value)

      SSH::ResponseSet.new.tap do |response_set|
        responses.each do |message|
          status, response = message

          case status
          when :ok
            response_set.add_ok(response)
          when :error
            response_set.add_error(response)
          end
        end
      end
    ensure
      pool.terminate if pool
    end
  end
end
