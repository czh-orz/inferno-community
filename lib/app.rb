require 'inferno-smart-launch'
require 'dm-core'
require_relative './sequence_extension'

def self.property(name, type, default=nil)
	if default.nil? then
		Inferno::Models::TestingInstance.send("property", name, type) 
	else
		Inferno::Models::TestingInstance.send("property", name, type, default) 
	end
end

property :dynamically_registered, DataMapper::Property::Boolean


DataMapper.auto_upgrade!


Inferno::Sequence::SequenceBase.send("include", SequenceExtension)

Inferno::Sequence.load_sequences(__dir__)
Inferno::Module.load_modules(__dir__)

Inferno::App::Endpoint::Landing.send("set", :modules, ['onc'])