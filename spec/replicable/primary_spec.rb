require 'spec_helper'
require 'support/models'

# TODO Parent is not affected by child fields
# TODO no tail on the key

describe Replicable::Primary do
  before { load 'support/fake_amqp.rb' }
  context "when creating" do
    let!(:instance) { Test::Primary::Child.create(:child_field_1  => "child_1",
                                                  :child_field_2  => "child_2",
                                                  :parent_field_1 => "parent_1",
                                                  :parent_field_3 => "dont care") }

    it "broadcasts the model hierarchy in the key" do
      root, model_name, operation, fields = Replicable::AMQP.messages.last[:key].split('.')
      model_name.split(',').should =~ ['test/primary/child', 'test/primary/parent']
    end

    it "broadcasts the create operation in the key" do
      root, model_name, operation, fields = Replicable::AMQP.messages.last[:key].split('.')
      operation.should == 'create'
    end

    it "broadcasts the changed field names in the key" do
      root, model_name, operation, fields = Replicable::AMQP.messages.last[:key].split('.')
      fields.split(',').should =~ ['child_field_1', 'child_field_2', 'parent_field_1']
    end

    it "broadcasts the changes in the payload" do
      Replicable::AMQP.messages.last[:payload].should == { :id             => instance.id,
                                                           :child_field_1  => "child_1",
                                                           :child_field_2  => "child_2",
                                                           :parent_field_1 => "parent_1" }
    end
  end

  context "when updating" do
    let!(:instance) { Test::Primary::Child.create }

    before do
      Replicable::AMQP.clear
      instance.update_attributes(:child_field_1  => "child_1",
                                 :child_field_2  => "child_2",
                                 :parent_field_1 => "parent_1",
                                 :parent_field_3 => "dont care")
    end

    it "broadcasts the model hierarchy in the key" do
      root, model_name, operation, fields = Replicable::AMQP.messages.last[:key].split('.')
      model_name.split(',').should =~ ['test/primary/child', 'test/primary/parent']
    end

    it "broadcasts the update operation in the key" do
      root, model_name, operation, fields = Replicable::AMQP.messages.last[:key].split('.')
      operation.should == 'update'
    end

    it "broadcasts the changed field names in the key" do
      root, model_name, operation, fields = Replicable::AMQP.messages.last[:key].split('.')
      fields.split(',').should =~ ['child_field_1', 'child_field_2', 'parent_field_1']
    end

    it "broadcasts the changes in the payload" do
      Replicable::AMQP.messages.last[:payload].should == { :id             => instance.id,
                                                           :child_field_1  => "child_1",
                                                           :child_field_2  => "child_2",
                                                           :parent_field_1 => "parent_1" }
    end
  end

  context "when destroying" do
    let!(:instance) { Test::Primary::Child.create }

    before do
      Replicable::AMQP.clear
      instance.destroy
    end

    it "broadcasts the model hierarchy in the key" do
      root, model_name, operation, fields = Replicable::AMQP.messages.last[:key].split('.')
      model_name.split(',').should =~ ['test/primary/child', 'test/primary/parent']
    end

    it "broadcasts the update operation in the key" do
      root, model_name, operation, fields = Replicable::AMQP.messages.last[:key].split('.')
      operation.should == 'destroy'
    end

    it "broadcasts the id in the payload" do
      Replicable::AMQP.messages.last[:payload].should == { :id => instance.id }
    end
  end
end
