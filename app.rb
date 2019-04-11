require 'inferno-fhir'

Inferno::Models::TestingInstance.add_property(:test_property, String)
DataMapper.auto_upgrade!
Inferno::Sequence.load_sequences(__dir__)
Inferno::Module.load_modules(__dir__)

#Dir.glob(File.join(__dir__, 'modules', '**', '*_sequence.rb')).each{|file| require file}
Rack::Handler::Thin.run Inferno::App.new