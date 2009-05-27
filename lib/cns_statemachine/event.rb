module CnsStatemachine
  module Event
    class Event
      attr_accessor :active_object
      attr_accessor :event_data
      attr_accessor :publishing_time
      attr_accessor :event_type
      attr_accessor :when_condition
      attr_accessor :test_condition_defferation

      def initialize event_type_or_event_data, active_object
        @event_data = EventData.new
        @publishing_time = 0
        @when_condition = nil
        @test_condition_defferation = false
        @active_object = active_object
        
        if event_type_or_event_data.is_a?(EventType)
          event_type = event_type_or_event_data
          
          local_cluster = active_object
          
          @event_type = event_type
        elsif event_type_or_event_data.is_a?(EventData)
          event_data = event_type_or_event_data
          
          local_cluster = active_object

          @event_type = active_object.event_type.find(event_data.event_type_name)
          
          after = event_data.after
          
          when_condition = event_data.when_condition
          
          event_data.parameters.each do |name, value|
            set name, value
          end
        else
          raise event_type_or_event_data.inspect
        end

        @event_data.event_type_name = @event_type.name
      end

      def get name
        @event_data.parameters.get name
      end
      
      def after 
        @event_data.after
      end
      
      def is_deferred_through_condition
        if test_condition_defferation
          if after + publishing_time <= Time.now.to_i
            result = nil
            
            begin
              result = when_condition.call
            rescue => exception
              raise "10011 #{exception.inspect}"
            end
            
            test_condition_defferation = !( result.blank? || result == true )
          end
        else
          return false
        end
        
        return test_condition_defferation
      end
      
      def null? name
        return !!@event_data.parameters.get(name)
      end
      
      def publish
        active_object.publish self
      end
      
      def set name, value
        tmp = Parameter::Parameter.new event_type.get_parameter_type(name), active_object
        
        tmp.set value
        
        @event_data.parameters[name] = tmp.get
        
        return self
      end
      
      def after= new_after
        @event_data.after = new_after
      end
      
      def local_cluster= new_active_object
        @active_object = new_active_object
      end
      
      def test_conditioned_defferation= new_test_conditioned_defferation
        if new_test_conditioned_defferation
          publishing_time = Time.now.to_i
        end
        
        test_conditioned_defferation = new_test_conditioned_defferation
      end
      
      def event_type= new_type
        event_data.event_type_name = new_type.name
        
        @event_type = new_type
        
        parameter = {}
        
        @event_type.parameter_type.each do |p_type|
          parameter[p_type.name] = Parameter.new(p_type, active_object).get
        end
        
        event_data.parameters = parameter
      end
      
      def when_condition= when_action
        event_data.when_condition = when_action
        
        when_condition = Kernel.lambda when_action # TODO this is for testing, delete after working
        
        begin
          when_condition = Kernel.lambda when_action
        rescue => exception 
          raise "10012 #{{:when => when_action}} #{exception.inspect}"
        end
      end
        
      def to_s
        event_data.to_s
      end
    end

    class EventData
      attr_accessor :after
      attr_accessor :parameters
      attr_accessor :event_type_name
      attr_accessor :when_condition

      def initialize
        @after = 0
        @parameters = {}
        @event_type_name = nil
        @when_condition = nil
      end
      
      def parameter_names
        parameters.keys
      end
      
      def after= new_after
        new_after = 0 if new_after.blank?
        new_after = new_after.to_i if new_after.is_a?(String)
        @after = new_after
      end
      
      def to_s
        "EventData <name: <#{event_type_name}> parameter:<#{parameters.to_s}>>"
      end
    end

    class EventHandler
      attr_accessor :process_list
      attr_accessor :publish
      attr_accessor :parent_state
      attr_accessor :guard_context
      attr_accessor :guard
      attr_accessor :event_type
      attr_accessor :context
      attr_accessor :transition
      attr_accessor :active_object

      def initialize parent_state, context, process_classes
        @process_list = []
        @publish = []
        @parent_state = parent_state
        @guard_context = nil
        @guard = nil
        @event_type = nil
        @context = context
        @transition = nil
        @active_object = parent_state.active_object
        
        @process_classes ||= []
        
        (process_classes || []).each do |tmp|
          begin
            @process_list << tmp.new(self)
          rescue => exception
            raise "10034 #{exception.inspect}"
          end
        end
      end

      def execute event
        CnsBase.logger.debug("execute <#{event.event_type.name}> event in #{parent_state.name} #{transition.blank? ? "": " with transition to #{transition.name}"}") if CnsBase.logger.debug?
        CnsBase.logger.debug("context: #{context}") if CnsBase.logger.debug?

        begin
          time = Time.now.to_i
          
          process_array = []
          
          process_list.each do |process|
            break unless process.execute(event, context)
          end
          
          time = Time.now.to_i - time
          
          publish.each do |pub|
            pub.publish event
          end
        rescue
          raise "10036 #{$!.inspect} #{($!.backtrace || []).join("\n")} #{{:state => parent_state.name, :event_name => event.event_type.name, :context => (context.blank? ? nil : context.to_s), :transition => (transition.blank? ? "no transition" : transition.name)}.inspect}"
        end
      end

      def transition
        if @transition && @transition.active_object.blank?
          transition_to = @transition.name
          
          @transition = active_object.state_by_name[transition_to]
          
          if @transition.blank?
            raise "10037 transition: #{transition_to.inspect}"
          end
        end
        
        @transition
      end
      
      def dispatchable? event
        begin
          return event_type.is_type?(event) && (guard.blank? || guard.execute(event, guard_context))
        rescue => exception
          raise "10047 event_name: #{event.event_data.event_type_name}"
        end
      end
      
      def event_type= event_type_or_event_name
        if event_type_or_event_name.is_a?(EventType)
          @event_type = event_type_or_event_name
        else
          event_name = event_type_or_event_name
          raise "10038 state: #{parent_state.name}" if event_name.blank? || (@transition && (event_name == ActiveObject::SIG_STATE_ENTRY || event_name == ActiveObject::SIG_STATE_EXIT))
          @event_type = active_object.get_event_type event_name
          raise "10038 state: #{parent_state.name}" if @event_type.blank?
        end
      end
      
      def guard= guard_context
        if guard_context.blank?
          @guard_context = nil
          @guard = nil
        else
          @guard_context = guard_context
          @guard = Action::EvalProcess.new(self)
        end
      end
      
      def transition= new_transition
        if new_transition.is_a?(State)
          @transition = new_transition
        else
          new_transition = nil if new_transition.blank?
          
          @transition = new_transition.blank? ? nil : State::State.new
          
          @transition.name = new_transition if @transition

          raise "10039 state: #{parent_state.name}" if @transition && (@event_type.name == AO::ActiveObject::SIG_STATE_ENTRY || @event_type.name == AO::ActiveObject::SIG_STATE_EXIT)
        end
      end
    end

    class EventType
      attr_accessor :inheritated_event_types
      attr_accessor :name
      attr_accessor :parameter_types
      attr_accessor :parent

      def initialize
        @inheritated_event_types = []
        @name = nil
        @parameter_types = []
        @parent = nil
      end
      
      def find event_name
        return self if name == event_name
        
        result = @inheritated_event_types.collect do |event_type|
          event_type.find(event_name)
        end.compact
        
        raise if result.size > 1
        
        result.first
      end
      
      def parameter_types
        @parameter_types + (parent.blank? ? [] : parent.parameter_types)
      end
      
      def get_parameter_type parameter_name
        parameter_types.find do |parameter_type|
          parameter_type.name == parameter_name
        end
      end
      
      def is_type? event
        return true if event.event_type.name == name
        
        return parent.is_type?(event) if parent
        
        return false
      end
    end

    class Publish
      attr_accessor :active_object
      attr_accessor :event_data
      attr_accessor :event_handler
      attr_accessor :setters

      def initialize event_handler
        @event_handler = event_handler
        @active_object = event_handler.active_object
        @event_data = nil
        @setters = {}
      end
      
      def publish event
        new_event = Event.new event_data, active_object
        
        setters.each do |name, value|
          if value.is_a?(Array) && value.size == 2 && [:esv, :params].include?(value.first)
            ename = value.last
            
            if value.first == :esv
              esv = event_handler.parent_state.esvs.find{|esv|esv.name == ename}
              new_event.set(name, esv.blank? ? nil : esv.parameter.get)
            elsif value.first == :params
              new_event.set(name, event.event_data.parameters[ename])
            end
          else
            new_event.set(name, value)
          end
        end
        
        new_event.publish
      end
      
      def set_event_data event_name, setters
        @event_data = active_object.new_event(event_name).event_data
        @setters = setters
      end
    end
  end
end
