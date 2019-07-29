module TopologicalInventory::Azure
  class Parser
    module Vm
      def parse_vms(data, scope)
        instance = data[:vm]

        uid           = instance.id
        flavor        = lazy_find(:flavors, :source_ref => instance.hardware_profile.vm_size) if instance.hardware_profile.vm_size
        _subscription = lazy_find(:subscriptions, :source_ref => scope[:subscription_id])

        power_state   = 'unknown' unless (power_state = raw_power_state(instance.instance_view))

        vm = TopologicalInventoryIngressApiClient::Vm.new(
          :source_ref    => uid,
          :uid_ems       => uid,
          :name          => instance.name || uid,
          :power_state   => parse_vm_power_state(power_state),
          :flavor        => flavor,
          # :subscription => subscription, # TODO(lsmola) do the modeling first
          :mac_addresses => parse_network(data)[:mac_addresses]
        )

        collections[:vms].data << vm
        parse_vm_tags(uid, instance.tags)
      end

      private

      def raw_power_state(instance_view)
        instance_view&.statuses&.detect { |s| s.code.start_with?('PowerState/') }&.code
      end

      def parse_network(instance)
        # TODO(lsmola) we can set this from .primary interface
        network = {
          :fqdn                 => nil,
          :private_ip_address   => nil,
          :public_ip_address    => nil,
          :mac_addresses        => [],
          :private_ip_addresses => [],
          :public_ip_addresses  => [],
        }

        (instance[:network_interfaces] || []).each do |interface|
          network[:mac_addresses] << interface.mac_address
          interface.ip_configurations.each do |private_ip|
            network[:private_ip_addresses] << private_ip.private_ipaddress
            # TODO(lsmola) getting .public_ipaddress is another n+1 query, do we want it?
            # network[:public_ip_addresses] << nil
          end
        end

        network
      end

      def parse_vm_tags(vm_uid, tags)
        (tags || []).each do |key, value|
          collections[:vm_tags].data << TopologicalInventoryIngressApiClient::VmTag.new(
            :vm  => lazy_find(:vms, :source_ref => vm_uid),
            :tag => lazy_find(:tags, :name => key, :value => value, :namespace => "azure")
          )
        end
      end

      def parse_vm_power_state(state)
        case state
        when "PowerState/running"
          "on"
        when "PowerState/stopping"
          "powering_down"
        when "PowerState/deallocating"
          "terminating"
        when "PowerState/deallocated"
          "terminated"
        when "PowerState/stopped", "PowerState/starting"
          "off"
        else
          "unknown"
        end
      end
    end
  end
end