# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/event_aggregator'
require 'new_relic/agent/attribute_processing'
require 'new_relic/agent/sampled_buffer'

module NewRelic
  module Agent
    class CustomEventAggregator < EventAggregator
      include NewRelic::Coerce

      TYPE             = 'type'.freeze
      TIMESTAMP        = 'timestamp'.freeze
      PRIORITY         = 'priority'.freeze
      EVENT_TYPE_REGEX = /^[a-zA-Z0-9:_ ]+$/.freeze

      named :CustomEventAggregator
      capacity_key :'custom_insights_events.max_samples_stored'
      enabled_key :'custom_insights_events.enabled'
      buffer_class PrioritySampledBuffer

      def record(type, attributes)
        unless attributes.is_a? Hash
          raise ArgumentError, "Expected Hash but got #{attributes.class}"
        end

        return unless enabled?

        type = @type_strings[type]
        unless type =~ EVENT_TYPE_REGEX
          note_dropped_event(type)
          return false
        end

        priority = attributes[:priority] || rand

        event = [
          { TYPE => type, TIMESTAMP => Time.now.to_i,
            PRIORITY => priority
          },
          AttributeProcessing.flatten_and_coerce(attributes)
        ]

        stored = @lock.synchronize do
          @buffer.append(event: event, priority: priority)
        end
        stored
      end

      private

      def after_initialize
        @type_strings = Hash.new { |hash, key| hash[key] = key.to_s.freeze }
      end

      def after_harvest metadata
        dropped_count = metadata[:seen] - metadata[:captured]
        note_dropped_events(metadata[:seen], dropped_count)
        record_supportability_metrics(metadata[:seen], metadata[:captured], dropped_count)
      end

      def note_dropped_events total_count, dropped_count
        if dropped_count > 0
          NewRelic::Agent.logger.warn("Dropped #{dropped_count} custom events out of #{total_count}.")
        end
      end

      def record_supportability_metrics total_count, captured_count, dropped_count
        engine = NewRelic::Agent.instance.stats_engine
        engine.tl_record_supportability_metric_count("Events/Customer/Seen"   ,    total_count)
        engine.tl_record_supportability_metric_count("Events/Customer/Sent"   , captured_count)
        engine.tl_record_supportability_metric_count("Events/Customer/Dropped",  dropped_count)
      end

      def note_dropped_event(type)
        ::NewRelic::Agent.logger.log_once(:warn, "dropping_event_of_type:#{type}",
          "Invalid event type name '#{type}', not recording.")
        @buffer.note_dropped
      end
    end
  end
end
