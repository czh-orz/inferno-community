module InstanceExtension
  def fhir_version
    self.module.fhir_version
  end

  def patient_id
    self.resource_references.select{|ref| ref.resource_type == 'Patient'}.first.try(:resource_id)
  end

  def patient_id= patient_id
    return if patient_id.to_s == self.patient_id.to_s

    existing_patients = self.resource_references.select{|ref| ref.resource_type == 'Patient'}
    # Use destroy directly (instead of on each, so we don't have to reload)
    self.resource_references.destroy
    self.save!

    self.resource_references << ResourceReference.new({
                                                          resource_type: 'Patient',
                                                          resource_id: patient_id
                                                      })

  end

  def save_supported_resources(conformance)
    resources = ['Patient',
                 'AllergyIntolerance',
                 'CarePlan',
                 'Condition',
                 'Device',
                 'DiagnosticReport',
                 'DocumentReference',
                 'ExplanationOfBenefit',
                 'Goal',
                 'Immunization',
                 'Medication',
                 'MedicationDispense',
                 'MedicationStatement',
                 'MedicationOrder',
                 'Observation',
                 'Procedure',
                 'DocumentReference',
                 'Provenance']

    supported_resources = conformance.rest.first.resource.select{ |r| resources.include? r.type}.reduce({}){|a,k| a[k.type] = k; a}

    self.supported_resources.each(&:destroy)
    self.save!

    resources.each_with_index do |resource_name, index|

      resource = supported_resources[resource_name]

      read_supported = resource && resource.interaction && resource.interaction.any?{|i| i.code == 'read'}

      self.supported_resources << SupportedResource.create({
                                                               resource_type: resource_name,
                                                               index: index,
                                                               testing_instance_id: self.id,
                                                               supported: !resource.nil?,
                                                               read_supported: read_supported,
                                                               vread_supported: resource && resource.interaction && resource.interaction.any?{|i| i.code == 'vread'},
                                                               search_supported: resource && resource.interaction && resource.interaction.any?{|i| i.code == 'search-type'},
                                                               history_supported: resource && resource.interaction && resource.interaction.any?{|i| i.code == 'history-instance'}
                                                           })
    end

    self.save!

  end

  def conformance_supported?(resource, methods = [])

    resource_support = self.supported_resources.find {|r| r.resource_type == resource.to_s}
    return false if resource_support.nil? || !resource_support.supported

    methods.all? do |method|
      case method
      when :read
        resource_support.read_supported
      when :search
        resource_support.search_supported
      when :history
        resource_support.history_supported
      when :vread
        resource_support.vread_supported
      else
        false
      end
    end
  end

  def post_resource_references(resource_type: nil, resource_id: nil)
    self.resource_references.each do |ref|
      if (ref.resource_type == resource_type) && (ref.resource_id == resource_id)
        ref.destroy
      end
    end
    self.resource_references << ResourceReference.new({resource_type: resource_type,
                                                      resource_id: resource_id})
    self.save!
    # Ensure the instance resource references are accurate
    self.reload
  end
end