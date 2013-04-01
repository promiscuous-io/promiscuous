require 'spec_helper'

if ORM.has(:mongoid)
  describe Promiscuous do
    before { use_real_backend }
    before { load_models }
    before { record_callbacks(SubscriberModel) }

    before { run_subscriber_worker! }

    context 'when not using a context' do
      it 'raises' do
        expect { PublisherModel.create }.to raise_error(Promiscuous::Error::MissingContext)
      end
    end

    context 'when doing a blank update' do
      it 'passes through' do
        pub = Promiscuous.context { PublisherModel.create(:field_1 => '1') }
        eventually { SubscriberModel.first.should_not == nil }
        Mongoid.purge!
        expect { Promiscuous.context { pub.update_attributes(:field_1 => '2') } }.to_not raise_error
      end
    end

    context 'when doing a blank destroy' do
      it 'passes through' do
        pub = Promiscuous.context { PublisherModel.create(:field_1 => '1') }
        eventually { SubscriberModel.first.should_not == nil }
        Mongoid.purge!
        expect { Promiscuous.context { pub.destroy } }.to_not raise_error
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

    context 'when using / in the value' do
      it 'replicates' do
        Promiscuous.context do
          pub = PublisherModel.create(:field_1 => '/hi')
          eventually { SubscriberModel.first.field_1.should == '/hi' }
          pub.update_attributes(:field_2 => '/hel/lo/')
          eventually { SubscriberModel.first.field_2.should == '/hel/lo/' }
          pub.update_attributes(:field_3 => 'hello/')
          eventually { SubscriberModel.first.field_3.should == 'hello/' }
          pub.update_attributes(:field_1 => '/')
          eventually { SubscriberModel.first.field_1.should == '/' }

          dep = pub.promiscuous.tracked_dependencies.first.tap { |d| d.version = 123 }
          dep.redis_node.get(dep.key(:sub).join('rw').to_s).to_i.should == 4
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

          dep = pub.promiscuous.tracked_dependencies.first.tap { |d| d.version = 123 }
          dep.redis_node.get(dep.key(:sub).join('rw').to_s).to_i.should == 4
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

    context 'when processing half duplicated messages' do
      before { config_logger :logger_level => Logger::FATAL }

      context 'when completing half of the secondaries' do
        it 'skips duplicates' do
          pub = nil
          PublisherModel.track_dependencies_of :field_2
          pub = Promiscuous.context { PublisherModel.create(:field_2 => 'hello') }
          eventually { SubscriberModel.num_saves.should == 1 }

          @num_deps = 10

          Promiscuous::Subscriber::Operation.any_instance.stubs(:after_secondary_update_hook).raises
          Promiscuous.context do
            @num_deps.times.map { |i| PublisherModel.where(:field_2 => i.to_s).count }
            pub.update_attributes(:field_1 => '1')
          end
          sleep 1
          Promiscuous::Subscriber::Operation.any_instance.unstub(:after_secondary_update_hook)

          Promiscuous.context { pub.update_attributes(:field_1 => '2') }

          @worker.pump.recover # this will retry the message
          eventually { SubscriberModel.first.field_1.should == '2' }

          @num_deps.times.map { |i| Promiscuous::Dependency.new('publisher_models', 'field_2', i.to_s) }
            .each { |dep| dep.redis_node.get(dep.key(:sub).join('rw').to_s).should == '1' }
        end
      end

      context 'when completing all the secondaries' do
        it 'skips duplicates' do
          pub = nil
          PublisherModel.track_dependencies_of :field_2
          pub = Promiscuous.context { PublisherModel.create(:field_2 => 'hello') }
          eventually { SubscriberModel.num_saves.should == 1 }

          @num_deps = 10

          Promiscuous::Subscriber::Operation.any_instance.stubs(:update_dependencies_single).raises
          Promiscuous.context do
            @num_deps.times.map { |i| PublisherModel.where(:field_2 => i.to_s).count }
            pub.update_attributes(:field_1 => '1')
          end
          sleep 1
          Promiscuous::Subscriber::Operation.any_instance.unstub(:update_dependencies_single)

          Promiscuous.context { pub.update_attributes(:field_1 => '2') }

          @worker.pump.recover # this will retry the message
          eventually { SubscriberModel.first.field_1.should == '2' }

          @num_deps.times.map { |i| Promiscuous::Dependency.new('publisher_models', 'field_2', i.to_s) }
            .each { |dep| dep.redis_node.get(dep.key(:sub).join('rw').to_s).should == '1' }
        end
      end
    end

    context 'when processing duplicate messages' do
      it 'skips duplicates' do
        pub = nil
        pub = Promiscuous.context { PublisherModel.create }
        Promiscuous.context { pub.update_attributes(:field_1 => '2') }
        eventually { SubscriberModel.num_saves.should == 2 }

        dep = pub.promiscuous.tracked_dependencies.first
        key = dep.key(:pub)
        dep.redis_node.decr(key.join('rw').to_s)
        dep.redis_node.decr(key.join('w').to_s)

        Promiscuous.context { pub.update_attributes(:field_1 => '3') } # skipped update
        Promiscuous.context { pub.update_attributes(:field_1 => '4') } # processed update

        eventually do
          SubscriberModel.first.field_1.should == '4'
          SubscriberModel.num_saves.should == 3
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
        Promiscuous.context { pub.update_attributes(:field_1 => '2') }
        eventually { SubscriberModel.num_saves.should == 2 }

        without_promiscuous { pub.inc(:_pv, 1) }
        dep = pub.promiscuous.tracked_dependencies.first
        key = dep.key(:pub)
        dep.redis_node.incr(key.join('rw').to_s)
        dep.redis_node.incr(key.join('w').to_s)

        Promiscuous.context { pub.update_attributes(:field_1 => '3') }
        Promiscuous.context { pub.update_attributes(:field_1 => '4') }
        Promiscuous.context { pub.update_attributes(:field_1 => '5') }
        Promiscuous.context { pub.update_attributes(:field_1 => '6') }
        Promiscuous.context { pub.update_attributes(:field_1 => '7') }

        eventually do
          SubscriberModel.first.field_1.should == '7'
          SubscriberModel.num_saves.should == 7
        end
      end
    end
  end
end
