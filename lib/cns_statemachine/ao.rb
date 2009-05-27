module CnsStatemachine
  module AO
    module AOEventBranch
      def attach
        raise
      end
      
      def detach
        raise
      end
      
      def putLIFO event
        raise
      end
      
      def tick
        raise
      end
    end
  
    module AOEventSource
      def publish event
        raise
      end
      
      def stop
        raise
      end
    end
    
    class ActiveObject
      # Lifecircle:
      #
      # new ActiveObject
      # add event_type
      # register states
      # 
      # attach
      # publish new_event()
      # tick tick tick
      # 
      # detach
      
      include AOEventBranch
      include AOEventSource
    
      SIG_INITIAL_STATE = :SIG_INITIAL_STATE
      SIG_STATE_ENTRY = :SIG_STATE_ENTRY
      SIG_STATE_EXIT = :SIG_STATE_EXIT
      SIG_FLEXIBLE_TRANSITION = :SIG_FLEXIBLE_TRANSITION
      SIG_EXCEPTION = :SIG_EXCEPTION
    
      attr_accessor :event_queue
      attr_accessor :event_type
      attr_accessor :ao_event_source
      attr_accessor :attached
      attr_accessor :state_by_name
      attr_accessor :state_machine
      attr_accessor :active_nested_sub_state
      attr_accessor :state_path_by_state

      def initialize
        @event_queue = CnsStatemachine::Queue.new
        @event_type = Event::EventType.new
        @event_type.name = :TOP_LEVEL_EVENT_TYPE
        @ao_event_source = nil
        @attached = false
        @state_by_name = {}
        @state_machine = nil
        @active_nested_sub_state = nil
        @state_path_by_state = {}

        # create atomic events
        create_atomic_event_type_sub ActiveObject::SIG_EXCEPTION, [:exception, :event]
        create_atomic_event_type_sub ActiveObject::SIG_FLEXIBLE_TRANSITION, [:transition]
        create_atomic_event_type_sub ActiveObject::SIG_INITIAL_STATE, []
        create_atomic_event_type_sub ActiveObject::SIG_STATE_ENTRY, []
        create_atomic_event_type_sub ActiveObject::SIG_STATE_EXIT, []
      end

      def create_atomic_event_type_sub name, params
        event_type = Event::EventType.new

        event_type.name = name
        event_type.parent = @event_type

        params.each do |param|
          parameter_type = Parameter::ParameterType.new

          parameter_type.name = param
          parameter_type.ok_null = true
          parameter_type.event_type_or_state = event_type

          event_type.parameter_types << parameter_type
        end
        
        @event_type.inheritated_event_types << event_type
      end

      # creation
      def register_state state
        raise unless stopped?
        
        old = @state_by_name[state.name]

        if old
          raise "10014: " + {:name => state.name, :registered_parent => (state.parent.blank? ? "" : state.parent.name), :new_parent => (old.parent.blank? ? "" : old.parent.name)}.inspect
        end
        
        @state_by_name[state.name] = state

        state_path = []
        position = state
        
        while position
          state_path << position
          position = position.parent
        end
        
        @state_path_by_state[state] = state_path.reverse!
      end

      # start/stop
      def attach
        CnsBase.logger.debug("attaching #{state_machine.name}") if CnsBase.logger.debug?
        
        @attached = true
        @active_nested_sub_state = state_machine
        @state_machine.attach
        
        return stopped?
      end
      
      def detach
        CnsBase.logger.debug("detaching #{state_machine.name}") if CnsBase.logger.debug?
        
        @attached = false
        @state_machine.detach
        @event_queue.clear
      end
      
      def stopped?
        not @attached
      end

      def stop cause
        if @attached
          if @ao_event_source
            @ao_event_source.stop cause
          else
            CnsBase.logger.warn("Engine stopped. #{cause.inspect}") if CnsBase.logger.warn?
            
            begin 
              detach
            rescue => exception
              CnsBase.logger.fatal("Detaching failed. #{exception.inspect}") if CnsBase.logger.fatal?
            end
            
            exit
          end
        else
          CnsBase.logger.fatal("Detaching failed. #{exception.inspect}") if CnsBase.logger.fatal?
        end
      end

      def tick
        return false if stopped?
      
        tick_orthogonal @state_machine
      
        raise "10015" if @event_queue.locked?
      
        event_queue_object = @event_queue.get
      
        processed = false
        
        while event_queue_object && !processed
          event = event_queue_object.get
          
          if event.is_deferred_through_condition
            event_queue_object = @event_queue.deferr event_queue_object
            raise "10016"
          else
            result = :failed
            exception = nil
            
            begin
              result = active_nested_sub_state.dispatch event
            rescue => e
              exception = e
            end
          
            if result == :deferred
              event_queue_object = @event_queue.deferr event_queue_object
            elsif result == :failed
              @event_queue.acknowledge event_queue_object
              raise exception
            else
              @event_queue.acknowledge event_queue_object
              processed = true
            end
          end
        end

        return processed
      end
      
      def tick_orthogonal state
        result = false
        
        result = true if state.is_a?(State::OrthogonalState) && state.tick
        
        result = true if state.active_direct_sub_state && tick_orthogonal(state.active_direct_sub_state)
        
        return result
      end

      # event publishing
      def new_event event_name
        event_type = @event_type.find(event_name)
        
        raise "unknown event #{event_name}" unless event_type
        
        Event::Event.new event_type, self
      end
      
      def publish event_or_event_data
        event_data = event_or_event_data.is_a?(Event::Event) ? event_or_event_data.event_data : event_or_event_data
        
        if @ao_event_source
          @ao_event_source.publish event_data
        else
          putLIFO(event_data)
        end
      end
      
      def putFIFO event
        CnsBase.logger.debug("putFIFO #{event.event_type.name}") if CnsBase.logger.debug?

        raise if stopped?
        
        @event_queue.putFIFO(event)
      end
      
      def putLIFO event_or_event_data
        CnsBase.logger.debug("putLIFO #{event_or_event_data.is_a?(Event::Event) ? event_or_event_data.event_type.name : event_or_event_data.event_type_name} in #{@state_machine.name}") if CnsBase.logger.debug?
        
        raise if stopped?
        
        event = event_or_event_data.is_a?(Event::Event) ? event_or_event_data : Event::Event.new(event_or_event_data, self)
        
        @event_queue.putLIFO(event)
        
        state = @active_nested_sub_state
        
        while state
          state.putLIFO(event.event_data) if state.is_a? State::OrthogonalState
          state = state.parent
        end
      end
      
      # yaml
      def as_yaml
        raise
      end
      
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
      def from_yaml yaml_or_hash
        hash = yaml_or_hash.is_a?(String) ? YAML.load(yaml_or_hash) : yaml_or_hash
        
        from_yaml_event_type @event_type, hash[:event_types]
        
        states = from_yaml_states self, nil, hash[:states], hash[:event_types]
        
        raise "top state hash must contain exactly one state (the top state)" unless states.size == 1
        
        @state_machine = states.first
      end
      
      #  {
      #    :state1 =>
      #    {
      #      :esvs => SEE from_yaml_params,
      #      :history => State::HISTORY_DEEP,
      #      :defer => [:event1],
      #      :on_events => SEE from_yaml_on_event,
      #      :states => 
      #      {
      #        SAME AS from_yaml_states (SUBSTATES)
      #      },
      #      :orthogonal => [{LIKE from_yaml_states}],
      #      :external => [{Can be e.g a cluster}]
      #    }
      #  }
      def from_yaml_states active_object, parent, hash, event_types_hash
        hash ||= {}
        
        hash.collect do |name, properties|
          if properties.include?(:orthogonal_states) || properties.include?(:external)
            state = State::OrthogonalState.new
          else
            state = State::State.new
          end
          
          state.name = name
          state.parent = parent
          state.active_object = active_object
          state.history_type = properties[:history]

          state.esvs = from_yaml_esvs(active_object, state, properties[:esvs])

          state.event_handlers = from_yaml_on_event state, properties[:on_events]
          state.deferred_event_types = (properties[:defer] || []).collect{|defer|@event_type.find(defer)}

          state.sub_states = from_yaml_states active_object, state, properties[:states], event_types_hash
          
          if properties.include?(:orthogonal_states)
            orthogonals = properties[:orthogonal_states]
            
            orthogonals = [orthogonals] if orthogonals.is_a?(Hash)
            
            orthogonals.each do |orthogonal|
              active_object.from_yaml_orthogonal_states state, orthogonal, event_types_hash
            end
          end
          
          if properties.include?(:external)
            externals = properties[:external]
            
            externals = [externals] if externals.is_a?(Hash)
            
            externals.each do |external|
              active_object.from_yaml_external state, external
            end
          end
          
          raise "not supported" if properties[:cluster]
          
          state
        end
      end
      
      def from_yaml_orthogonal_states parent, hash, event_types_hash
        if @ao_event_source
          @ao_event_source.from_yaml_orthogonal_states parent, hash, event_types_hash
        else
          CnsBase.logger.warn("from_yaml_orthogonal_states should implemented by the ao event source") if CnsBase.logger.warn?
        end
      end
      
      def from_yaml_external parent, hash
        if @ao_event_source
          @ao_event_source.from_yaml_external parent, hash
        else
          CnsBase.logger.warn("from_yaml_external should implemented by the ao event source") if CnsBase.logger.warn?
        end
      end
      
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
      def from_yaml_on_event state, on_events
        on_events ||= {}
        
        on_events.collect do |name, on_event|
          on_event = [on_event] unless on_event.is_a?(Array)

          on_event.collect do |params|
            context = params[:context]
            processes = params[:processes]
            
            processes = [Action::EvalProcess] if (processes.blank? || processes.empty?) && context.blank? == false
            
            event_handler = Event::EventHandler.new state, context, processes

            event_handler.guard = params[:guard]
            
            event_handler.event_type = state.active_object.event_type.find(name)
            
            event_handler.transition = params[:transition]
            event_handler.publish = (params[:publish] || []).collect{|publish|from_yaml_publish event_handler, publish}.flatten
            
            event_handler
          end
        end.flatten
      end
      
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
      def from_yaml_publish event_handler, hash
        hash ||= {}
        
        hash.collect do |name, params|
          publish = Event::Publish.new event_handler
        
          publish.set_event_data name, params[:setters] || {}
        
          publish.setters
          
          raise "not supported" if params[:after]
          raise "not supported" if params[:end_point_url]
          
          publish
        end
      end
      
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
      def from_yaml_event_type parent, hash
        hash ||= {}
        
        result = hash.collect do |event_name, properties|
          event_type = Event::EventType.new
          
          event_type.name = event_name
          event_type.parent = parent
          
          event_type.parameter_types = from_yaml_params(event_type, properties[:params])

          from_yaml_event_type(event_type, properties[:event_types])
          
          event_type
        end
        
        parent.inheritated_event_types += result
        
        result
      end
      
      # :var1 => 
      # {
      #   :guard => "var1 > 5",
      #   :default => 5
      #   :ok_null => false
      # }
      def from_yaml_params event_type_or_state, hash
        hash ||= {}
        
        hash.collect do |parameter_name, parameter_properties|
          parameter_type = Parameter::ParameterType.new
          parameter_type.guard = parameter_properties[:guard]
          parameter_type.default_value = parameter_properties[:default]
          parameter_type.name = parameter_name
          parameter_type.event_type_or_state = event_type_or_state
          parameter_type.ok_null = parameter_properties[:ok_null]
          
          parameter_type
        end
      end
      def from_yaml_esvs active_object, event_type_or_state, hash
        hash ||= {}
        
        hash.collect do |parameter_name, parameter_properties|
          esv = Parameter::Esv.new(active_object)
          
          esv.guard = parameter_properties[:guard]
          esv.default_value = parameter_properties[:default]
          esv.name = parameter_name
          esv.event_type_or_state = event_type_or_state
          esv.ok_null = parameter_properties[:ok_null]

          esv.reset
          
          esv
        end
      end
    end
  end
end
