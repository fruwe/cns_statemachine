module CnsStatemachine
  module State
    class State
      HISTORY_SHALLOW_TYPE = "shallow"
      HISTORY_OFF = "off"
      HISTORY_DEEP_TYPE = "deep"
      HISTORY_STATE_SUFFIX = "__HISTORY"
      
      attr_accessor :sub_states
      attr_accessor :deferred_event_types
      attr_accessor :active_direct_sub_state
      attr_accessor :esvs
      attr_accessor :event_handlers
      attr_accessor :history_type
      attr_accessor :history
      attr_accessor :name
      attr_accessor :parent
      attr_accessor :active_object

      def initialize
        @sub_states = []
        @deferred_event_types = []
        @active_direct_sub_state = nil
        @esvs = []
        @event_handlers = []
        @history_type = nil
        @history = nil
        @name = nil
        @parent = nil
        @active_object = nil
      end
      
      def attach
        raise "10023" if @parent || @active_direct_sub_state
        
        entry_transition
        
        dispatch_local(active_object.new_event(AO::ActiveObject::SIG_INITIAL_STATE))
      end
      
      def detach
        raise "10025" if parent
        
        @active = @active_object.active_nested_sub_state
        
        while @active
          @active.exit_transition
          
          @active = @active.parent
        end
      end
      
      def dispatch event
        local = dispatch_local event
        
        if local
          local
        elsif parent
          @parent.dispatch(event)
        else
          raise event.get("exception") if event.event_type.name == AO::ActiveObject::SIG_EXCEPTION
          
          false
        end
      end
      
      def esvs
        if @parent
          @parent.esvs + @esvs
        else
          @esvs
        end
      end
      
      def publish_flexible_transition transition_to
        @active_object.putFIFO(@active_object.new_event(AO::ActiveObject::SIG_FLEXIBLE_TRANSITION).set("transition", transition_to.name))
      end
      
      def active_object= active_object
        @active_object = active_object
        
        @active_object.register_state self
      end
      
      def history_type= history_type
        history_type = HISTORY_OFF if history_type.blank?
        
        raise "10026" unless [HISTORY_SHALLOW_TYPE, HISTORY_DEEP_TYPE, HISTORY_OFF].include?(history_type)
        
        @history_type = history_type
        @history = nil
        
        return if @history_type == HISTORY_OFF
        
        @history = State.new
        
        event_handler = EventHandler.new @history, "", nil
        
        event_handler.active_object = active_object
        event_handler.event_type = AO::ActiveObject::SIG_INITIAL_STATE
        event_handler.transition = self
        
        @history.event_handlers << event_handler
        @history.active_object = active_object
        @history.name = name + HISTORY_STATE_SUFFIX
        @history.parent = self
        
        sub_states << @history
        
        active_object.register_state @history
      end
      
      def dispatch_local event
        CnsBase.logger.debug("dispatch local #{event.event_type.name}") if CnsBase.logger.debug?
        
        if event.event_type.name == AO::ActiveObject::SIG_FLEXIBLE_TRANSITION
          transition = event.get("transition")
          
          unless transition.blank?
            transition_to active_object.get_state(transition)
            
            unless name.ends_with?(HISTORY_STATE_SUFFIX)
              update_history
            end
          end
          
          return true
        else 
          event_handlers.each do |event_handler|
            if event_handler.dispatchable? event
              begin
                event_handler.execute(event)
              
                transition = event_handler.transition

                if transition
                  transition_to transition

                  unless name.to_s.starts_with? HISTORY_STATE_SUFFIX
                    update_history
                  end
                end
              rescue => exception
                if event.event_data.event_type_name == AO::ActiveObject::SIG_EXCEPTION
                  raise exception
                else
                  active_object.putFIFO(active_object.new_event(AO::ActiveObject::SIG_EXCEPTION).set("exception", exception).set("event", event.event_data))
                end
              end
              
              return true
            end
          end
        end

        return :deferred if deferred? event
        
        return false
      end
      
      def entry_transition
        CnsBase.logger.debug("ENTER STATE #{name}") if CnsBase.logger.debug?
        
        parent.active_direct_sub_state = self if parent
        
        active_object.active_nested_sub_state = self
        
        dispatch_local active_object.new_event(AO::ActiveObject::SIG_STATE_ENTRY)
      end
      
      def exit_transition
        CnsBase.logger.debug("EXIT STATE #{name}") if CnsBase.logger.debug?

        dispatch_local active_object.new_event(AO::ActiveObject::SIG_STATE_EXIT)
        
        @esvs.each do |esv|
          esv.reset
        end
        
        parent.active_direct_sub_state = nil if parent
        
        active_object.active_nested_sub_state = parent
      end
      
      def find_path_to_child state
        sub_states.find do |sub_state|
          sub_state == state || sub_state.find_path_to_child(state)
        end
      end
      
      def transition_to transition_to
        CnsBase.logger.debug("TRANSITION TO #{transition_to.name}") if CnsBase.logger.debug?
        
        start_state = active_object.active_nested_sub_state
        
        if start_state == transition_to
          start_state.exit_transition
          start_state.entry_transition
        else
          state_path_start = active_object.state_path_by_state[start_state]
          state_path_transition = active_object.state_path_by_state[transition_to]
          
          least_common_ancestor = (0...(state_path_start.size > state_path_transition.size ? state_path_start.size : state_path_transition.size)).find do |index|
            state_path_start[index] != state_path_transition[index]
          end

          exit_transitions = state_path_start[least_common_ancestor...state_path_start.size].reverse!
          entry_transitions = state_path_transition[least_common_ancestor...state_path_transition.size]

          exit_transitions.each do |state|
            state.exit_transition
          end
          
          entry_transitions.each do |state|
            state.entry_transition
          end
        end
        
        transition_to.dispatch_local active_object.new_event( AO::ActiveObject::SIG_INITIAL_STATE )
      end
      
      def deferred? event
        deferred_event_types.find do |event_type|
          event_type.is_type? event
        end
      end
      
      def update_history
        parent.update_history if parent
        
        history.event_handler.get(0).transition = active_object.active_nested_sub_state if history_type == HISTORY_DEEP_TYPE

        history.event_handler.get(0).transition = active_direct_sub_state if history_type == HISTORY_SHALLOW_TYPE
      end
    end

    class OrthogonalState < State
      attr_accessor :branches
      
      def initialize 
        super
        
        @branches = []
      end
      
      def add_AO_event_branch new_branch
        branches << new_branch
      end
      
      def putLIFO event_data
        branches.each do |branch|
          branch.putLIFO(event_data)
        end
      end
      
      def tick
        result = false
        branches.each do |branch|
          result = true if branch.tick
        end
      end
      
      def entry_transition
        super
        
        branches.each do |branch|
          branch.attach
        end
      end
      
      def exit_transition
        branches.each do |branch|
          branch.detach
        end

        super
      end
    end
  end
end
