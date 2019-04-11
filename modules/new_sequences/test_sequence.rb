module Inferno
    module Sequence
        class TestSequence < SequenceBase
            group 'ba'
            title 'test'
            description 'testing'
            test_id_prefix 'test'

            test 'Nothing' do 
                metadata{
                    id '01'
                    link 'asd'
                    desc 'asdasd'
                    versions :dstu2
                }
                var = @instance.state_variables.select{|var| var.name == 'another_one'}.first
                var.value = "testaa"
                var.save!
            end
        end
    end
end
