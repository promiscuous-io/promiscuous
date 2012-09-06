require 'spec_helper'

describe Promiscuous::Subscriber::Class, '.klass' do
  before { load_models }

  context 'when using a class finishing with Subscriber' do
    it 'uses the class name without Subscriber as target' do
      class SubscriberModelSubscriber < ORM::SubscriberBase; end
      SubscriberModelSubscriber.klass.should == SubscriberModel
    end
  end

  context 'when using a scope' do
    it 'uses the class name as target' do
      module Scope
        module Subscribers
          class SubscriberModel < ORM::SubscriberBase; end
        end
      end

      Scope::Subscribers::SubscriberModel.klass.should == ::SubscriberModel
    end

    it 'uses the name scoped class name as target' do
      module Scope
        module Subscribers
          module Scoped
            class ScopedSubscriberModel < ORM::SubscriberBase; end
          end
        end
      end

      Scope::Subscribers::Scoped::ScopedSubscriberModel.klass.should == ::Scoped::ScopedSubscriberModel
    end
  end
end
