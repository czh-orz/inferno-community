module Inferno
  module Sequence
    class SequenceBase
      def get_resource_by_params(klass, params = {})
        assert !params.empty?, "No params for search"
        options = {
          :search => {
            :flag => false,
              :compartment => nil,
              :parameters => params
          }
        }
        @client.search(klass, options)
      end

      def versioned_resource_class(klass)
        @client.versioned_resource_class klass
      end

      def check_sort_order(entries)
        relevant_entries = entries.select{|x|x.request.try(:local_method)!='DELETE'}
        relevant_entries.map!(&:resource).map!(&:meta).compact rescue assert(false, 'Unable to find meta for resources returned by the bundle')

        relevant_entries.each_cons(2) do |left, right|
          if !left.versionId.nil? && !right.versionId.nil?
            assert (left.versionId > right.versionId), 'Result contains entries in the wrong order.'
          elsif !left.lastUpdated.nil? && !right.lastUpdated.nil?
            assert (left.lastUpdated >= right.lastUpdated), 'Result contains entries in the wrong order.'
          else
            raise AssertionException.new 'Unable to determine if entries are in the correct order -- no meta.versionId or meta.lastUpdated'
          end
        end
      end

      def validate_resource_item (resource, property, value)
        assert false, "Could not validate resource"
      end

      def validate_search_reply(klass, reply, search_params)
        assert_response_ok(reply)
        assert_bundle_response(reply)

        entries = reply.resource.entry.select{ |entry| entry.resource.class == klass }
        assert entries.length > 0, 'No resources of this type were returned'

        if klass == versioned_resource_class('Patient') then
          assert !reply.resource.get_by_id(@instance.patient_id).nil?, 'Server returned nil patient'
          assert reply.resource.get_by_id(@instance.patient_id).equals?(@patient, ['_id', "text", "meta", "lastUpdated"]), 'Server returned wrong patient'
        end 

        entries.each do |entry|

          # This checks to see if the base resource conforms to the specification
          # It does not validate any profiles.
          base_resource_validation_errors = entry.resource.validate
          assert base_resource_validation_errors.empty?, "Invalid #{entry.resource.resourceType}: #{base_resource_validation_errors}"

          search_params.each do |key, value|
            validate_resource_item(entry.resource, key.to_s, value)
          end
        end
      end

      def save_resource_ids_in_bundle(klass, reply)
        return if reply.try(:resource).try(:entry).nil?

        entries = reply.resource.entry.select{ |entry| entry.resource.class == klass }

        entries.each do |entry|
          @instance.post_resource_references(resource_type: klass.name.split(':').last,
                                            resource_id: entry.resource.id)
        end
      end

      def validate_read_reply(resource, klass)
        assert !resource.nil?, "No #{klass.name.split(':').last} resources available from search."
        if resource.is_a? FHIR::DSTU2::Reference
          read_response = resource.read
        else
          id = resource.try(:id)
          assert !id.nil?, "#{klass} id not returned"
          read_response = @client.read(klass, id)
          assert_response_ok read_response
          read_response = read_response.resource
        end
        assert !read_response.nil?, "Expected valid #{klass} resource to be present"
        assert read_response.is_a?(klass), "Expected resource to be valid #{klass}"
      end

      def validate_history_reply(resource, klass)
        assert !resource.nil?, "No #{klass.name.split(':').last} resources available from search."
        id = resource.try(:id)
        assert !id.nil?, "#{klass} id not returned"
        history_response = @client.resource_instance_history(klass, id)
        assert_response_ok history_response
        assert_bundle_response history_response
        assert_equal "history", history_response.try(:resource).try(:type)
        entries = history_response.try(:resource).try(:entry)
        assert entries, 'No bundle entries returned'
        assert entries.try(:length) > 0, 'No resources of this type were returned'
        check_sort_order entries
      end

      def validate_vread_reply(resource, klass)
        assert !resource.nil?, "No #{klass.name.split(':').last} resources available from search."
        id = resource.try(:id)
        assert !id.nil?, "#{klass} id not returned"
        version_id = resource.try(:meta).try(:versionId)
        assert !version_id.nil?, "#{klass} version_id not returned"
        vread_response = @client.vread(klass, id, version_id)
        assert_response_ok vread_response
        assert !vread_response.resource.nil?, "Expected valid #{klass} resource to be present"
        assert vread_response.resource.is_a?(klass), "Expected resource to be valid #{klass}"
      end

      def test_resources_against_profile(resource_type, specified_profile=nil)
        @profiles_encountered = [] unless @profiles_encountered
        @profiles_failed = {} unless @profiles_failed

        all_errors = []

        resources = @instance.resource_references.select{|r| r.resource_type == resource_type}
        skip("Skip profile validation since no #{resource_type} resources found for Patient.") if resources.empty?

        @instance.resource_references.select{|r| r.resource_type == resource_type}.map(&:resource_id).each do |resource_id|

          resource_response = @client.read(versioned_resource_class(resource_type), resource_id)
          assert_response_ok resource_response
          resource = resource_response.resource
          assert resource.is_a?(versioned_resource_class(resource_type)), "Expected resource to be of type #{resource_type}"

          p = Inferno::ValidationUtil.guess_profile(resource, @instance.fhir_version.to_sym)
          if specified_profile
            next unless p.url == specified_profile
          end
          if p
            @profiles_encountered << p.url
            @profiles_encountered.uniq!
            errors = p.validate_resource(resource)
            @test_warnings.concat(p.warnings.reject(&:empty?))
            unless errors.empty?
              errors.map!{|e| "#{resource_type}/#{resource_id}: #{e}"}
              @profiles_failed[p.url] = [] unless @profiles_failed[p.url]
              @profiles_failed[p.url].concat(errors)
            end
            all_errors.concat(errors)
          else
            errors = entry.resource.validate
            all_errors.concat(errors.values)
          end
        end
        # TODO
        # bundle = client.next_bundle
        assert(all_errors.empty?, all_errors.join("<br/>\n"))
      end

      def validate_reference_resolutions(resource)
        problems = []

        walk_resource(resource) do |value, meta, path|
          next if meta["type"] != "Reference"
          begin
            # Should potentially update valid? method in fhir_dstu2_models
            # to check for this type of thing
            # e.g. "patient/54520" is invalid (fhir_client resource_class method would expect "Patient/54520")
            if value.relative?
              begin
                value.resource_class
              rescue NameError => e
                problems << "#{path} has invalid resource type in reference: #{value.type}"
                next
              end
            end
            value.read
          rescue ClientException => e
            problems << "#{path} did not resolve: #{e.to_s}"
          end
        end

        assert(problems.empty?, problems.join("<br/>\n"))
      end

      def check_resource_against_profile(resource, resource_type, specified_profile=nil)
        assert resource.is_a?("FHIR::DSTU2::#{resource_type}".constantize),
              "Expected resource to be of type #{resource_type}"

        p = Inferno::ValidationUtil.guess_profile(resource, @instance.fhir_version.to_sym)
        if specified_profile
          return unless p.url == specified_profile
        end
        if p
          @profiles_encountered << p.url
          @profiles_encountered.uniq!
          errors = p.validate_resource(resource)
          unless errors.empty?
            errors.map!{|e| "#{resource_type}/#{resource.id}: #{e}"}
            @profiles_failed[p.url] = [] unless @profiles_failed[p.url]
            @profiles_failed[p.url].concat(errors)
          end
        else
          errors = entry.resource.validate
        end
        assert(errors.empty?, errors.join("<br/>\n"))
      end
    end
  end
end