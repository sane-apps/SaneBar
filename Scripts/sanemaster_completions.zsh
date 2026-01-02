#compdef SaneMaster.rb sm

# SaneMaster Zsh Completion Script
# Installation:
#   1. Copy to ~/.zsh/completions/ (create if needed)
#   2. Add to ~/.zshrc: fpath=(~/.zsh/completions $fpath)
#   3. Run: autoload -Uz compinit && compinit
#   4. Restart terminal or run: source ~/.zshrc
#
# Or add alias to ~/.zshrc:
#   alias sm='./Scripts/SaneMaster.rb'
#   source /path/to/sanemaster_completions.zsh

_sanemaster() {
    local curcontext="$curcontext" state line
    typeset -A opt_args

    local -a commands
    commands=(
        # Build
        'verify:Build and run tests (unit by default, --ui for UI)'
        'clean:Wipe build cache and test states'
        'lint:Run SwiftLint and auto-fix issues'
        'audit:Scan for missing accessibility identifiers'

        # Generation
        'gen_test:Generate test file from template'
        'gen_mock:Generate mocks using Mockolo'
        'gen_assets:Generate test video assets'
        'template:Manage configuration templates'

        # Static Analysis
        'verify_api:Verify API exists in SDK'
        'dead_code:Find unused code (Periphery)'
        'deprecations:Scan for deprecated API usage'
        'swift6:Verify Swift 6 concurrency compliance'
        'check_docs:Check docs are in sync with code'
        'check_binary:Audit binary for security issues'

        # Debugging
        'test_mode:Kill → Build → Launch → Logs workflow'
        'tm:Alias for test_mode'
        'logs:Show application logs'
        'launch:Launch the app'
        'crashes:Analyze crash reports'
        'diagnose:Analyze .xcresult bundle'

        # Environment
        'doctor:Check environment health'
        'bootstrap:Full environment setup'
        'setup:Install gems and dependencies'
        'versions:Check tool versions'
        'reset:Reset TCC permissions'
        'restore:Fix Xcode/Launch Services issues'

        # Memory MCP
        'mc:Show memory context'
        'mr:Record new entity'
        'mp:Prune stale entities'

        # Export
        'export:Export code to PDF'
        'pdf:Alias for export'
        'deps:Show dependency graph'
        'quality:Generate Ruby quality report'

        # SOP Loop
        'verify_gate:Run verification gate'
        'vg:Alias for verify_gate'
        'sop_loop:Start SOP loop'
        'sop:Alias for sop_loop'

        # Help
        'help:Show help for category'
    )

    _arguments -C \
        '1: :->command' \
        '*: :->args'

    case $state in
        command)
            _describe -t commands 'SaneMaster command' commands
            ;;
        args)
            case $words[2] in
                verify)
                    _arguments \
                        '--ui[Run UI tests instead of unit tests]' \
                        '--clean[Clean build before testing]' \
                        '--help[Show command help]'
                    ;;
                clean)
                    _arguments \
                        '--nuclear[Also remove DerivedData]' \
                        '--help[Show command help]'
                    ;;
                export|pdf)
                    _arguments \
                        '--highlight[Enable syntax highlighting]' \
                        '--include-tests[Include test files]' \
                        '--output[Custom output directory]:directory:_files -/' \
                        '--no-compress[Skip PDF compression]' \
                        '--help[Show command help]'
                    ;;
                gen_test)
                    _arguments \
                        '--type[Test type]:type:(unit ui)' \
                        '--framework[Framework]:framework:(testing xctest)' \
                        '--target[Target class]:class:' \
                        '--async[Include async patterns]' \
                        '--help[Show command help]'
                    ;;
                gen_mock)
                    _arguments \
                        '--target[Target directory]:directory:_files -/' \
                        '--protocol[Protocol name]:protocol:' \
                        '--output[Output directory]:directory:_files -/' \
                        '--help[Show command help]'
                    ;;
                logs)
                    _arguments \
                        '--follow[Stream logs in real-time]' \
                        '--help[Show command help]'
                    ;;
                crashes)
                    _arguments \
                        '--recent[Show only recent crashes]' \
                        '--help[Show command help]'
                    ;;
                deps|dependencies)
                    _arguments \
                        '--dot[Output in DOT format]' \
                        '--help[Show command help]'
                    ;;
                template)
                    local -a subcommands
                    subcommands=(
                        'save:Save current config as template'
                        'apply:Apply template to project'
                        'list:List available templates'
                        'delete:Delete a template'
                    )
                    _describe -t subcommands 'template subcommand' subcommands
                    ;;
                help)
                    local -a categories
                    categories=(
                        'build:Build, test, and validate code'
                        'gen:Generate code, mocks, and assets'
                        'check:Static analysis and validation'
                        'debug:Debugging and crash analysis'
                        'env:Environment and setup'
                        'memory:Cross-session memory (MCP)'
                        'export:Export and documentation'
                    )
                    _describe -t categories 'help category' categories
                    ;;
                bootstrap|preflight|env)
                    _arguments \
                        '--check-only[Only check, do not install]' \
                        '--help[Show command help]'
                    ;;
                diagnose)
                    _arguments \
                        '--dump[Dump full contents]' \
                        '--path[Path to xcresult]:file:_files -g "*.xcresult"' \
                        '--help[Show command help]'
                    ;;
                mp|memory_prune)
                    _arguments \
                        '--dry-run[Show what would be pruned]' \
                        '--help[Show command help]'
                    ;;
                *)
                    _arguments '--help[Show command help]'
                    ;;
            esac
            ;;
    esac
}

# Register completion for both full path and alias
compdef _sanemaster './Scripts/SaneMaster.rb'
compdef _sanemaster 'sm'
