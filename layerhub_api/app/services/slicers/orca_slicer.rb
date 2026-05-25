# frozen_string_literal: true

require "open3"
require "fileutils"
require "json"

module Slicers
  class OrcaSlicer < BaseSlicer
    EXECUTABLE = ENV.fetch("ORCASLICER_PATH", "orca-slicer")

    # Built-in OrcaSlicer profiles used as base (Creality Ender-3 V3 is generic/well-supported)
    PROFILES_DIR = "/opt/orcaslicer/resources/profiles/Creality"
    MACHINE_PRESET = "#{PROFILES_DIR}/machine/Creality Ender-3 V3 0.4 nozzle.json"
    PROCESS_PRESET = "#{PROFILES_DIR}/process/0.20mm Standard @Creality Ender3V3 0.4 nozzle.json"

    # Maps UI setting keys to OrcaSlicer JSON keys (used in --load-settings JSON override)
    SETTING_MAP = {
      "layer_height"       => "layer_height",
      "first_layer_height" => "initial_layer_print_height",
      "infill"             => "sparse_infill_density",
      "infill_pattern"     => "sparse_infill_pattern",
      "wall_count"         => "wall_loops",
      "top_layers"         => "top_shell_layers",
      "bottom_layers"      => "bottom_shell_layers",
      "support"            => "enable_support",      "support_type"         => "support_type",      "support_density"    => "support_base_pattern_spacing",
      "brim_width"         => "brim_width",
      "skirt_loops"        => "skirt_loops",
      "print_speed"        => "outer_wall_speed",
      "nozzle_diameter"    => "nozzle_diameter"
    }.freeze

    def slice(input_path, output_path, profile: nil, settings: {})
      output_dir = File.dirname(output_path)
      process_path = build_process_preset(output_dir, settings)
      machine_path = build_machine_preset(output_dir, settings)
      cmd = build_command(input_path, output_dir, process_path, machine_path)
      run_command(cmd)

      gcode_file = find_gcode(output_dir)
      FileUtils.mv(gcode_file, output_path) unless gcode_file == output_path
    end

    private

    # Copy the base process preset and merge user overrides into it.
    # OrcaSlicer requires proper profile JSON with "type"/"from" fields.
    def build_process_preset(output_dir, settings)
      base = JSON.parse(File.read(PROCESS_PRESET))
      base["from"] = "user"

      (settings || {}).each do |key, value|
        orca_key = SETTING_MAP[key.to_s]
        next unless orca_key

        base[orca_key] = case key.to_s
        when "support"
          (value == true || value == "true" || value == "1") ? "1" : "0"
        when "infill"
          "#{value}%"
        else
          value.to_s
        end
      end

      # Always explicitly set brim_type to prevent OrcaSlicer's default
      # "auto_brim" behavior from adding unwanted brim.
      brim_w = (settings["brim_width"] || settings[:brim_width])
      if brim_w.nil? || brim_w.to_f.zero?
        base["brim_type"] = "no_brim"
        base["brim_width"] = "0"
      else
        base["brim_type"] = "outer_only"
      end

      path = File.join(output_dir, "process_override.json")
      File.write(path, JSON.pretty_generate(base))
      path
    end

    # Copy the machine preset with overridden bed dimensions.
    # IMPORTANT: The filename MUST match the original preset name so OrcaSlicer's
    # compatible_printers check passes (it derives the preset name from the filename).
    def build_machine_preset(output_dir, settings)
      w = (settings[:bed_width] || settings["bed_width"])&.to_i
      d = (settings[:bed_depth] || settings["bed_depth"])&.to_i

      return MACHINE_PRESET unless w && d && w > 0 && d > 0

      base = JSON.parse(File.read(MACHINE_PRESET))
      base["printable_area"] = ["0x0", "#{w}x0", "#{w}x#{d}", "0x#{d}"]

      # Keep the original filename so preset name matches compatible_printers
      path = File.join(output_dir, File.basename(MACHINE_PRESET))
      File.write(path, JSON.pretty_generate(base))
      path
    end

    def build_command(input_path, output_dir, process_path, machine_path = MACHINE_PRESET)
      parts = [
        EXECUTABLE,
        "--slice", "0",
        "--arrange", "0",
        "--load-settings", "\"#{machine_path};#{process_path}\"",
        "--outputdir", shell_escape(output_dir),
        shell_escape(input_path)
      ]
      parts.join(" ")
    end

    def find_gcode(output_dir)
      pattern = File.join(output_dir, "*.gcode")
      files = Dir.glob(pattern).sort_by { |f| File.mtime(f) }
      raise SliceError, "OrcaSlicer produced no G-code output in #{output_dir}" if files.empty?

      files.last
    end

    def shell_escape(path)
      Shellwords.escape(path)
    end
  end
end
