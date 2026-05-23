# frozen_string_literal: true

class GcodePostProcessor
  Result = Struct.new(:output_path, :estimated_time, :material_used, :layers_processed, :swaps_injected, keyword_init: true)

  # @param input_path   [String] path to the slicer-generated G-code
  # @param output_path  [String] path where the processed G-code will be written
  # @param color_swaps  [Array<Hash>] each with :layer_number, :pause_type, :color_label
  def initialize(input_path:, output_path:, color_swaps: [])
    @input_path = input_path
    @output_path = output_path
    @swap_map = build_swap_map(color_swaps)
    @current_layer = 0
    @estimated_time = nil
    @material_used = nil
    @swaps_injected = 0
  end

  # Processes the G-code file line-by-line (memory-efficient for 100MB+ files).
  # Injects pause/filament-swap commands at the specified layers.
  # @return [Result]
  def process
    File.open(@output_path, "w") do |out|
      File.foreach(@input_path) do |line|
        track_layer(line)
        extract_metadata(line)
        inject_swap(out) if @swap_map.key?(@current_layer) && layer_just_changed?(line)
        out.write(line)
      end
    end

    Result.new(
      output_path: @output_path,
      estimated_time: @estimated_time,
      material_used: @material_used,
      layers_processed: @current_layer,
      swaps_injected: @swaps_injected
    )
  end

  private

  def build_swap_map(color_swaps)
    color_swaps.each_with_object({}) do |swap, map|
      layer = swap[:layer_number] || swap["layer_number"]
      map[layer] = {
        pause_type: swap[:pause_type] || swap["pause_type"] || "M400 U1",
        color_label: swap[:color_label] || swap["color_label"] || "Color change"
      }
    end
  end

  # Detect layer changes via slicer comments (PrusaSlicer/BambuStudio format)
  def track_layer(line)
    case line
    when /^;LAYER_CHANGE/
      @layer_changing = true
    when /^;Z:([\d.]+)/
      @current_layer += 1 if @layer_changing
      @layer_changing = false
    end
  end

  def layer_just_changed?(line)
    # Inject right after the ;Z: line that confirms the layer change
    line.match?(/^;Z:/)
  end

  def inject_swap(out)
    swap = @swap_map.delete(@current_layer)
    return unless swap

    out.write("\n; >>> LayerHub: #{swap[:color_label]} at layer #{@current_layer}\n")
    out.write("#{swap[:pause_type]} ; Pause for filament swap\n")
    out.write("; <<< LayerHub\n")
    @swaps_injected += 1
  end

  # Extract metadata from slicer comment lines
  def extract_metadata(line)
    case line
    when /^;estimated printing time.*?=\s*(.+)/
      @estimated_time = Regexp.last_match(1).strip
    when /^;filament used.*?=\s*(.+)/
      @material_used = Regexp.last_match(1).strip
    end
  end
end
