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
        module Scope
          class SubscriberModel < ORM::SubscriberBase; end
        end
      end

      Scope::Scope::SubscriberModel.klass.should == ::SubscriberModel
    end
  end
end
