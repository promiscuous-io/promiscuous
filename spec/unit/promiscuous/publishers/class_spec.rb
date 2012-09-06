require 'spec_helper'

describe Promiscuous::Publisher::Class, '.klass' do
  before { load_models }

  context 'when using a class finishing with Publisher' do
    it 'uses the class name without Publisher as target' do
      class PublisherModelPublisher < ORM::PublisherBase; end
      PublisherModelPublisher.klass.should == ::PublisherModel
    end
  end

  context 'when using a scope' do
    it 'uses the class name as target' do
      module Scope
        module Publishers
          class PublisherModel < ORM::PublisherBase; end
        end
      end

      Scope::Publishers::PublisherModel.klass.should == ::PublisherModel
    end

    it 'uses the name scoped class name as target' do
      module Scope
        module Publishers
          module Scoped
            class ScopedPublisherModel < ORM::PublisherBase; end
          end
        end
      end

      Scope::Publishers::Scoped::ScopedPublisherModel.klass.should == ::Scoped::ScopedPublisherModel
    end
  end
end
