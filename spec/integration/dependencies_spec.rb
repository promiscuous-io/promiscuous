require 'spec_helper'

if ORM.has(:mongoid)
  describe Promiscuous do
    before { use_real_backend }
    before { load_models }
    before { record_callbacks(SubscriberModel) }

    before { run_subscriber_worker! }

    context 'when doing a blank update' do
      it 'passes through' do
        pub1 = Promiscuous.context { PublisherModel.create(:field_1 => '1') }
        eventually { SubscriberModel.first.should_not == nil }
        Mongoid.purge!
        expect { Promiscuous.context { pub1.update_attributes(:field_1 => '2') } }.to_not raise_error
      end
    end

    context 'when doing a blank destroy' do
      it 'passes through' do
        pub1 = Promiscuous.context { PublisherModel.create(:field_1 => '1') }
        eventually { SubscriberModel.first.should_not == nil }
        Mongoid.purge!
        expect { Promiscuous.context { pub1.destroy } }.to_not raise_error
      end
    end

    context 'when doing multi updates' do
      it 'fails immediately' do
        expect { Promiscuous.context { PublisherModel.update_all(:field_1 => '1') } }.to raise_error
      end
    end

    context 'when doing multi delete' do
      it 'fails immediately' do
        expect { Promiscuous.context { PublisherModel.delete_all(:field_1 => '1') } }.to raise_error
      end
    end

    context 'when doing parallel increments' do
      before do
        define_constant :Publisher do
          include Mongoid::Document
          include Promiscuous::Publisher
          publish { field :field }
        end

        define_constant :Subscriber do
          include Mongoid::Document
          include Promiscuous::Subscriber
          subscribe(:from => '*/publisher') { field :field }
          field :inc_by_one
          before_update { inc(:inc_by_one, 1) if field == field_was + 1 }
        end

        run_subscriber_worker!
      end

      it 'stays ordered' do
        pubs = 3.times.map { Promiscuous.context { Publisher.create(:field => 0) } }
        pubs.map do |pub|
          10.times.map { Thread.new { Promiscuous.context { 10.times { pub.inc(:field, 1) } } } }
        end.flatten.each(&:join)

        eventually :timeout => 10.seconds do
          Subscriber.count.should == 3
          Subscriber.all.each do |sub|
            sub.field.should == 100
            sub.inc_by_one.should == 100
          end
        end
      end
    end

    context 'when subscribing to a subset of models' do
      it 'replicates' do
        Promiscuous.context do
          PublisherModel.create
          PublisherModelOther.create
          PublisherModel.create
        end

        eventually do
          SubscriberModel.num_saves.should == 2
        end
      end
    end

    context 'when using : in the value' do
      it 'replicates' do
        Promiscuous.context do
          pub = PublisherModel.create(:field_1 => ':hi')
          eventually { SubscriberModel.first.field_1.should == ':hi' }
          pub.update_attributes(:field_2 => ':hel:lo:')
          eventually { SubscriberModel.first.field_2.should == ':hel:lo:' }
          pub.update_attributes(:field_3 => 'hello:')
          eventually { SubscriberModel.first.field_3.should == 'hello:' }
          pub.update_attributes(:field_1 => ':')
          eventually { SubscriberModel.first.field_1.should == ':' }

          dep = pub.promiscuous.tracked_dependencies.first
          Promiscuous::Redis.get(dep.key(:sub).to_s).to_i.should == 4
        end
      end
    end

    context 'when the publisher fails' do
      it 'replicates' do
        Promiscuous.context do
          pub1 = PublisherModel.create(:field_1 => '1')
          expect do
            PublisherModel.create({:id => pub1.id, :field_1 => '2'}, :without_protection => true)
          end.to raise_error
          pub3 = PublisherModel.create(:field_1 => '3')
        end

        eventually do
          SubscriberModel.count.should == 2
        end
      end
    end

    context 'when processing duplicate messages' do
      before { config_logger :logger_level => Logger::FATAL }

      it 'skips duplicates' do
        pub = nil
        pub = Promiscuous.context { PublisherModel.create }
        Promiscuous.context { pub.inc(:field_1, 1) }
        eventually { SubscriberModel.num_saves.should == 2 }

        key = pub.promiscuous.tracked_dependencies.first.key(:pub)
        Promiscuous::Redis.decr(key.join('rw').to_s)
        Promiscuous::Redis.decr(key.join('w').to_s)

        # Skipped update
        Promiscuous.context { pub.inc(:field_1, 1) }
        # processed update
        Promiscuous.context { pub.inc(:field_1, 1) }

        eventually do
          SubscriberModel.num_saves.should == 3
          SubscriberModel.first.field_1.should == 3
        end
      end
    end

    context 'when recovering' do
      before do
        config_logger :logger_level => Logger::FATAL
        Promiscuous::Config.prefetch = 5
        Promiscuous::Config.recovery = true
      end

      it 'increments versions properly' do
        pub = nil
        pub = Promiscuous.context { PublisherModel.create }
        Promiscuous.context { pub.inc(:field_1, 1) }
        eventually { SubscriberModel.num_saves.should == 2 }

        key = pub.promiscuous.tracked_dependencies.first.key(:pub)
        Promiscuous::Redis.incr(key.join('rw').to_s)
        Promiscuous::Redis.incr(key.join('w').to_s)

        5.times { Promiscuous.context { pub.inc(:field_1, 1) } }

        eventually do
          SubscriberModel.num_saves.should == 7
        end
      end
    end
  end
end
