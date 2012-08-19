require 'spec_helper'

describe Promiscuous::Publisher::ClassBind, '.klass' do
  before { load_models }

  context 'when using a class finishing with Publisher' do
    it 'uses the class name without Publisher as target' do
      class PublisherModelPublisher < ORM::PublisherBase
        publish :to => 'crowdtap/publisher_model',
          :attributes => [:field_1, :field_2, :field_3]
      end

      PublisherModelPublisher.klass.should == ::PublisherModel
    end
  end

  context 'when using a scope' do
    it 'uses the class name as target' do
      module Scope
        module Scope
          class PublisherModel < ORM::PublisherBase
            publish :to => 'crowdtap/publisher_model',
              :attributes => [:field_1, :field_2, :field_3]
          end
        end
      end

      Scope::Scope::PublisherModel.klass.should == ::PublisherModel
    end
  end
end
