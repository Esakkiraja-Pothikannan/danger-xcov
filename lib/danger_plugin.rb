module Danger
  # Validates the code coverage of the files changed within a Pull Request and
  # generates a brief coverage report.
  #
  # @example Validating code coverage for EasyPeasy (easy-peasy.io)
  #
  #    # Checks the coverage for the EasyPeasy scheme within the specified
  #    # workspace, ignoring the target 'Demo.app' and setting a minimum
  #    # coverage percentage of 90%.
  #   
  #    # The result is sent to the pull request with a markdown format and
  #    # notifies failure if the minimum coverage threshold is not reached.
  #
  #    xcov.report(
  #      scheme: 'EasyPeasy',
  #      workspace: 'Example/EasyPeasy.xcworkspace',
  #      exclude_targets: 'Demo.app',
  #      minimum_coverage_percentage: 90,
  #      minimum_coverage_percentage_for_changed_files: 80.0,
  #      ignore_list_of_minimum_coverage_percentage_for_changed_files: ['View', 'Cell', 'Layout', 'Action', 'State'],
  #    )
  #
  # @tags xcode, coverage, xccoverage, tests, ios, xcov
  # @see nakiostudio/danger-xcov
  #
  class DangerXcov < Plugin
    # Validates the code coverage of the files changed within a Pull Request.
    # This method accepts the same arguments allowed by the xcov gem.
    #
    # @param   args Hash{Symbol => String}
    #          This method accepts the same arguments accepted by the xcov gem.
    #          A complete list of parameters allowed is available here:
    #          https://github.com/nakiostudio/xcov
    # @return  [void]
    #
    def report(*args)
      # Run xcov to produce a processed report
      report = produce_report(*args)
      # Output the processed report
      output_report(report, *args)
    end
  
    # Produces and processes a report for use in the report method
    # It takes the same arguments as report, and returns the same
    # object as process_report
    def produce_report(*args)
      # Check xcov availability, install it if needed
      `gem install xcov` unless xcov_available?
      unless xcov_available?
        puts "xcov is not available on this machine"
        return
      end

      require "xcov"
      require "fastlane_core"

      # Init Xcov
      config = FastlaneCore::Configuration.create(Xcov::Options.available_options, convert_options(args.first))
      Xcov.config = config
      Xcov.ignore_handler = Xcov::IgnoreHandler.new

      # Init project
      report_json = nil
      manager = Xcov::Manager.new(config)

      if Xcov.config[:html_report] || Xcov.config[:markdown_report] || Xcov.config[:json_report]
        # Parse .xccoverage and create local report
        report_json = manager.run
      else
        # Parse .xccoverage
        report_json = manager.parse_xccoverage
      end

      # Map and process report
      process_report(Xcov::Report.map(report_json))
    end

    # Outputs a processed report with Danger
    def output_report(report, *args)

      report.print_description
      # Create markdown
      puts "::DONE::report.print_description"
      display_only_average_coverage = args.first[:display_only_average_coverage] || false
      puts "display_only_average_coverage: #{display_only_average_coverage}"
      average_coverage_target_title = args.first[:average_coverage_target_title] || ""
      puts "average_coverage_target_title: #{average_coverage_target_title}"
      if display_only_average_coverage && average_coverage_target_title.length > 0
        puts "INSIDE IF CONDITAION"
        report_markdown = average_coverage_markdown_value(report.targets, average_coverage_target_title, report.displayable_coverage)
      else
        puts "INSIDE ELSE CONDITAION"
        report_markdown = report.markdown_value
      end

      # Send markdown
      puts "report_markdown added:: #{report_markdown}"
      markdown(report_markdown)

      puts "Notify failure if minimum coverage hasn't been reached"
      # Notify failure if minimum coverage hasn't been reached
      threshold = Xcov.config[:minimum_coverage_percentage].to_i
      puts "Notify threshold: #{threshold}"
      if !threshold.nil? && (report.coverage * 100) < threshold
        puts "Notify threshold: (report.coverage * 100) < threshold"
        fail("Code coverage under minimum of #{threshold}%")
      end

      puts "Notify failure if minimum coverage hasn't been reached for modified/added files"
      # Notify failure if minimum coverage hasn't been reached for modified/added files
      file_threshold = args.first[:minimum_coverage_percentage_for_changed_files].to_i || 0
      puts "Notify file_threshold: #{file_threshold}"
      ignore_list = args.first[:ignore_list_of_minimum_coverage_percentage_for_changed_files] || []
      puts "Notify ignore_list: #{ignore_list}"

      if file_threshold > 0
        puts "file_threshold IF CONDITIONS: file_threshold > 0"
        report.targets.each do |target|
          target_files = target.files.select { |file| ignore_list.none? { |contains| file.name.include? contains } }
          violations = target_files.select { |file| (file.coverage * 100) < file_threshold }
          fail("Class code coverage is below minimum, please improve #{violations.map {|f| f.name }} to at least #{file_threshold}%.") if !violations.empty?
        end
        puts "END---1"
      end
      puts "END---2"
    end

    # Aux methods

    # Checks whether xcov is available
    def xcov_available?
      `which xcov`.split("/").count > 1
    end

    # Filters the files that haven't been modified in the current PR
    def process_report(report)
      file_names = @dangerfile.git.modified_files.map { |file| File.expand_path(file) }
      file_names += @dangerfile.git.added_files.map { |file| File.expand_path(file) }
      report.targets.each do |target|
        target.files = target.files.select { |file| file_names.include?(file.location) }
      end

      report
    end

    # Processes the parameters passed to the plugin
    def convert_options(options)
      converted_options = options.dup
      converted_options.delete(:verbose)
      converted_options.delete(:minimum_coverage_percentage_for_changed_files)
      converted_options.delete(:ignore_list_of_minimum_coverage_percentage_for_changed_files)
      converted_options
    end

    def average_coverage_markdown_value(targets, name, displayable_coverage)
      puts"average_coverage_markdown_value::: #{name} -- #{displayable_coverage}"
      markdown = "## Current coverage for #{name} is `#{displayable_coverage}`\n"
      puts"average_coverage_markdown_value::: markdown -- #{markdown}"
      changed_files_markdown = "#{targets.map { |target| each_target_changed_files_markdown_value(target.files) }.join("")}"
      if changed_files_markdown.length > 0
        markdown << "#{changed_files_markdown}"
      else
        markdown << "✅ *No files affecting coverage found*\n\n---\n"
      end
      markdown <<  "\n> Powered by [xcov](https://github.com/nakiostudio/xcov)"
      puts"average_coverage_markdown_value::: markdown111 -- #{markdown}"
      
      markdown
    end

    def each_target_changed_files_markdown_value(files)
      puts "each_target_changed_files_markdown_value"
      markdown = ""
      return markdown if files.empty?
      puts "each_target_changed_files_markdown_value -- 1111"
      markdown << "Files changed | - | - \n--- | --- | ---\n"
      puts "each_target_changed_files_markdown_value:: FILES CHANGED:: #{markdown}"
      markdown << "#{files.map { |file| file.markdown_value }.join("")}\n---\n"
      puts "each_target_changed_files_markdown_value:: FILES.MAP:: #{markdown}"

      markdown
    end

    private :xcov_available?, :process_report

  end
end
