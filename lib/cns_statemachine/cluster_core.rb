#  {
#    :states =>
#    {
#      SEE from_yaml_states
#    },
#  
#    :event_types =>
#    {
#      SEE from_yaml_event_type
#    }
#  }

#  {
#    :state1 =>
#    {
#      :esvs => SEE from_yaml_params,
#      :history => State::HISTORY_DEEP,
#      :defer => [:event1],
#      :on_event => SEE from_yaml_on_event,
#      :states => 
#      {
#        SAME AS from_yaml_states (SUBSTATES)
#      },
#      :cluster => ???
#    }
#  }

#  {
#    :event1 => # here can be an array of hashes or just a hash (as guards can be different)
#    [
#      {
#        :guard => "esvs[:esv1] > 1",
#        :context => "esvs[:esv1] += 1",
#        :processes => [EvalProcess],
#        :publish => [SEE from_yaml_publish],
#        :transition => :state1
#      }
#    ]
#  }

#  :event1 => 
#  {
#    :setters =>
#    {
#      :var1 => "hello",
#      :var2 => :esv1
#    },
#    :after => 1000,
#    :end_point_url => "http://"
#  }

# :sample_event =>
# {
#   :params => 
#   {
#     SEE from_yaml_params
#   },
#   :event_types => 
#   {
#     SAME AS from_yaml_event_type, BUT INHERITATES PARENT VARS
#   }
# }
#

# :var1 => 
# {
#   :guard => "var1 > 5",
#   :default => 5
#   :ok_null => false
# }

module CnsStatemachine
  module ClusterCore
    module Signals
      class QFSignal < CnsBase::Signal
        def initialize
          super
        end
      end
  
      class QFSignalAttach < QFSignal
        def initialize
          super
        end
      end
  
      class QFSignalDetach < QFSignal
        def initialize
          super
        end
      end

      class QFSignalEvent < QFSignal
        attr_accessor :event_data
        
        def initialize event_data
          super()
          
          @event_data = event_data
        end
      end

      class QFSignalException < QFSignal
        attr_accessor :exception
        
        def initialize exception
          super
          
          @exception = exception
        end
      end

      class QFSignalPublish < QFSignalEvent
        def initialize event_data
          super event_data
        end
      end

      class QFSignalPutLIFO < QFSignalEvent
        def initialize event_data
          super event_data
        end
      end

      class QFSignalTick < QFSignal
        def initialize
          super
        end
      end
    end

    class StatemachineClusterCore < CnsBase::Cluster::ClusterCore
      include Signals
      include CnsBase::Cas
      include CnsBase::Cluster
      include CnsBase::Address
      include Event
      include AO::AOEventSource
  
      attr_accessor :active_object
      attr_accessor :ticking
      attr_accessor :current_signal
      attr_accessor :top
  
      def initialize publisher
        super publisher
    
        @active_object = nil
        @ticking = false
        @current_signal = nil
        @top = true
      end
  
      def dispatch signal
        CnsBase.logger.debug("STATEMACHINE CORE: #{signal.class.name}") if CnsBase.logger.debug?
        CnsBase.logger.debug("STATEMACHINE CORE: #{@active_object.state_machine.name}") if @active_object && CnsBase.logger.debug?
        CnsBase.logger.debug("STATEMACHINE CORE: #{signal.signal.class.name}") if signal.respond_to?(:signal) && CnsBase.logger.debug?
        
        begin
          if signal.is_a?(ClusterCreationSignal)
            @active_object = AO::ActiveObject.new
            
            @active_object.ao_event_source = self
            
            core = signal.params
            core ||= {}
            
            @top = core.delete(:top) if core.include?(:top)

            @active_object.from_yaml core
            
            if @top
              signal = QFSignalAttach.new
            else
              return true
            end
          end
          
          return false unless @active_object
    
          if @current_signal
            return false
          end
    
          @current_signal = signal

          if signal.is_a? QFSignalPublish
            CnsBase.logger.debug("STATEMACHINE PUBLISH: #{signal.event_data.event_type_name}") if CnsBase.logger.debug?
            @active_object.publish signal.event_data
        
            if @ticking == false && @active_object.stopped? == false
              publisher.publish(QFSignalTick.new)
              @ticking = true
            end
          elsif signal.is_a? QFSignalPutLIFO
            @active_object.putLIFO signal.event_data
        
            if @ticking == false && @active_object.stopped? == false
              publisher.publish(QFSignalTick.new)
              @ticking = true
            end
          elsif signal.is_a? QFSignalAttach
            @active_object.attach
        
            if @ticking == false
              publisher.publish(QFSignalTick.new)
              @ticking = true
            end
          elsif signal.is_a? QFSignalDetach
            @active_object.detach
          elsif signal.is_a? QFSignalTick
            if @active_object.tick && @active_object.stopped? == false
              publisher.publish(QFSignalTick.new)
              @ticking = true
            else
              @ticking = false
            end
          elsif signal.is_a? QFSignalException
            @active_object.stop signal.exception
          else
            CnsBase.logger.debug("STATEMACHINE EVENT: #{signal.name}") if CnsBase.logger.debug?

            unless @active_object.event_type.find(signal.name)
              CnsBase.logger.fatal("STATEMACHINE EVENT: Event unknown, thus not handled") if CnsBase.logger.debug?
              
              return false
            end  
            
            event_data = EventData.new
        
            event_data.event_type_name = signal.name
            event_data.parameters = signal.params
        
            @active_object.putLIFO event_data
        
            if @ticking == false && @active_object.stopped? == false
              publisher.publish(QFSignalTick.new)
              @ticking = true
            end
          end
        rescue => exception
          publisher.publish(CnsBase::ExceptionSignal.new(exception, signal))
        ensure
          @current_signal = nil
        end
    
        return true
      end
  
      def publish event
        begin
          if @active_object && @top
            @active_object.putLIFO event

            publisher.publish( 
              AddressRouterSignal.new(
                CnsBase::Signal.new(
                  event.event_type_name, 
                  event.parameters 
                ),
                PublisherSignalAddress.new(publisher), 
                URISignalAddress.new( "/stub_control_cluster" ) 
              )
            )
          else
            publisher.publish( 
              AddressRouterSignal.new(
                QFSignalPublish.new(event),
                PublisherSignalAddress.new(publisher), 
                RoutedSignalAddress.new(AddressRouterSupportListener::CLIENTS) 
              )
            )
          end
        rescue => exception
          # TODO do not understand why @current_signal becomes nil... MUST BE WITHOUT if
          publisher.publish(CnsBase::ExceptionSignal.new(exception, @current_signal)) if @current_signal
        end
      end
  
      def stop exception
        if @top
          CnsBase.logger.warn("Statemachine stopped. #{exception.inspect}") if CnsBase.logger.warn?
          CnsBase.logger.warn("Try detaching...") if CnsBase.logger.warn?
      
          begin
            @active_object.detach
          rescue e
            CnsBase.logger.fatal("Detaching failed... #{e.inspect}") if CnsBase.logger.fatal?
          end
      
          publisher.publish(CnsBase::ExceptionSignal.new(exception, @current_signal))
        else
          publisher.publish(
            AddressRouterSignal.new(
              QFSignalException.new(cause),
              PublisherSignalAddress.new(publisher), 
              RoutedSignalAddress.new(AddressRouterSupportListener::CLIENTS) 
            )
          )
        end
      end
      
      def from_yaml_orthogonal_states orthogonal_state, hash, event_types_hash
        new_core = {
          :class => CnsStatemachine::ClusterCore::StatemachineClusterCore,
          :params =>
          {
            :top => false,
            :states => hash,
            :event_types => event_types_hash
          },            
          :uri => "/a/orthogonal_state#{CnsBase.uuid}"
        }
        
        from_yaml_external orthogonal_state, new_core
      end
      
      def from_yaml_external orthogonal_state, hash
        publisher.publish CnsBase::Address::AddressRouterSignal.new(
          CnsBase::Cluster::ClusterCreationSignal.new(hash[:class], hash[:params]),
          CnsBase::Address::PublisherSignalAddress.new(publisher),
          CnsBase::Address::URISignalAddress.new(hash[:uri])
        )

        orthogonal_state.add_AO_event_branch WebAOEventBranch.new(self, hash[:uri])
      end
    end
    
    class WebAOEventBranch
      include Signals
      include CnsBase::Cas
      include CnsBase::Cluster
      include CnsBase::Address
      include AO::AOEventBranch

      attr_accessor :cluster_core
      attr_accessor :to_uri

      def initialize cluster_core, to_uri
        super()
    
        @cluster_core = cluster_core
        @to_uri = to_uri
      end
  
      def attach
        cluster_core.publisher.publish( 
          AddressRouterSignal.new(
            QFSignalAttach.new,
            PublisherSignalAddress.new( cluster_core.publisher ), 
            URISignalAddress.new( to_uri ) 
          )
        )
    
        return true
      end
  
      def detach
        cluster_core.publisher.publish( 
          AddressRouterSignal.new(
            QFSignalDetach.new,
            PublisherSignalAddress.new( cluster_core.publisher ), 
            URISignalAddress.new( to_uri ) 
          )
        )
      end
  
      def putLIFO event
        cluster_core.publisher.publish( 
          AddressRouterSignal.new(
            QFSignalPutLIFO.new(event),
            PublisherSignalAddress.new( cluster_core.publisher ), 
            URISignalAddress.new( to_uri ) 
          )
        )
      end
  
      def tick
        false
      end
    end
  end
end