# frozen_string_literal: true

class SliceWorker
  include Sidekiq::Job
  sidekiq_options queue: :slicing, retry: 1

  def perform(slice_job_id)
    job = SliceJob.find(slice_job_id)
    job.slicing!

    Dir.mktmpdir("layerhub") do |tmpdir|
      input_path = download_source(job, tmpdir)
      sliced_path = File.join(tmpdir, "sliced.gcode")
      output_path = File.join(tmpdir, "processed.gcode")

      # Step 1: Run the slicer
      slicer = resolve_slicer(job.slicer)
      slicer.slice(input_path, sliced_path)

      # Step 2: Post-process the G-code
      job.post_processing!
      swaps = job.color_swaps.map do |cs|
        { layer_number: cs.layer_number, pause_type: cs.pause_type, color_label: cs.color_label }
      end

      result = GcodePostProcessor.new(
        input_path: sliced_path,
        output_path: output_path,
        color_swaps: swaps
      ).process

      # Step 3: Attach output and update metadata
      job.output_gcode.attach(
        io: File.open(output_path),
        filename: "#{job.print_asset.name.parameterize}-processed.gcode",
        content_type: "text/x-gcode"
      )
      job.update!(
        status: :completed,
        estimated_time: result.estimated_time,
        material_used: result.material_used
      )
    end
  rescue Slicers::BaseSlicer::SliceError, StandardError => e
    job&.update!(status: :failed, error_message: e.message.truncate(1000))
    raise # re-raise so Sidekiq can track the failure
  end

  private

  def download_source(job, tmpdir)
    source = job.print_asset.source_file
    raise "No source file attached to print asset #{job.print_asset_id}" unless source.attached?

    ext = File.extname(source.filename.to_s)
    path = File.join(tmpdir, "input#{ext}")
    File.open(path, "wb") { |f| f.write(source.download) }
    path
  end

  def resolve_slicer(slicer_name)
    case slicer_name
    when "prusa_slicer"  then Slicers::PrusaSlicer.new
    when "bambu_studio"  then Slicers::BambuStudio.new
    else raise "Unknown slicer: #{slicer_name}"
    end
  end
end
