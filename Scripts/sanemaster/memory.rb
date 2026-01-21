# frozen_string_literal: true

# ==============================================================================
# Memory Module (DEPRECATED - Jan 2026)
# ==============================================================================
# Memory MCP has been removed. Memory learnings are now auto-captured by
# Sane-Mem (localhost:37777).
#
# This stub module exists to prevent errors from `include SaneMasterModules::Memory`
# in SaneMaster.rb. All methods show deprecation notices.
# ==============================================================================

module SaneMasterModules
  module Memory
    DEPRECATION_NOTICE = <<~MSG

      ================================================================
      DEPRECATED: Memory MCP removed (Jan 2026)

      Memory learnings are now auto-captured by Sane-Mem (localhost:37777).
      These CLI commands no longer function.

      For memory management, use Sane-Mem directly or via hooks.
      ================================================================

    MSG

    def show_memory_context_summary
      # No-op: Memory MCP removed
    end

    def show_memory_context(_args)
      warn DEPRECATION_NOTICE
    end

    def record_memory_entity(_args)
      warn DEPRECATION_NOTICE
    end

    def prune_memory_entities(_args)
      warn DEPRECATION_NOTICE
    end

    def memory_health(_args = [])
      warn DEPRECATION_NOTICE
    end

    def memory_compact(_args)
      warn DEPRECATION_NOTICE
    end

    def check_memory_size_warning
      # No-op: Memory MCP removed
    end

    def memory_cleanup(_args)
      warn DEPRECATION_NOTICE
    end

    def auto_memory_check(_args = [])
      # No-op: Memory MCP removed
    end

    def memory_archive_stats(_args = [])
      warn DEPRECATION_NOTICE
    end

    def auto_record_fix(_name, _observations)
      # No-op: Memory MCP removed
    end

    def auto_record_architecture(_name, _observations)
      # No-op: Memory MCP removed
    end

    def auto_record_concurrency(_name, _observations)
      # No-op: Memory MCP removed
    end

    def auto_record(_entity_type, _name, _observations)
      # No-op: Memory MCP removed
    end

    def suggest_memory_record
      # No-op: Memory MCP removed
    end

    private

    # Stub private methods to prevent NoMethodError
    def show_entity_group(*); end
    def find_stale_entities(*); []; end
    def estimate_tokens(*); 0; end
    def find_verbose_entities(*); []; end
    def find_duplicate_candidates(*); []; end
  end
end
