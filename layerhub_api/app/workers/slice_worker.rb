# frozen_string_literal: true

class SliceWorker
  include Sidekiq::Job
  sidekiq_options queue: :slicing, retry: 1

  def perform(slice_job_id, settings = {})
    job = SliceJob.find(slice_job_id)

    # Acquire a row-level lock and atomically transition to :slicing.
    # If another worker already claimed this job, bail out.
    job.with_lock do
      return unless job.pending?
      job.slicing!
    end

    Dir.mktmpdir("layerhub") do |tmpdir|
      # Use scene file (combined STL with transforms) if available,
      # otherwise fall back to the original asset source file
      input_path = if job.scene_file.attached?
        download_scene(job, tmpdir)
      else
        download_source(job, tmpdir)
      end
      sliced_path = File.join(tmpdir, "sliced.gcode")
      output_path = File.join(tmpdir, "processed.gcode")

      # Step 1: Run the slicer
      slicer = resolve_slicer(job.slicer)
      slicer.slice(input_path, sliced_path, settings: settings.symbolize_keys)

      # Step 2: Post-process the G-code
      job.with_lock { job.post_processing! }
      swaps = job.color_swaps.map do |cs|
        { layer_number: cs.layer_number, pause_type: cs.pause_type, color_label: cs.color_label }
      end

      result = GcodePostProcessor.new(
        input_path: sliced_path,
        output_path: output_path,
        color_swaps: swaps
      ).process

      # Step 3: Attach output and update metadata (locked to prevent duplicate attachments)
      job.with_lock do
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
    end
  rescue Exception => e
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

  def download_scene(job, tmpdir)
    path = File.join(tmpdir, "scene.stl")
    File.open(path, "wb") { |f| f.write(job.scene_file.download) }
    path
  end

  def resolve_slicer(slicer_name)
    case slicer_name
    when "orca_slicer"   then Slicers::OrcaSlicer.new
    when "prusa_slicer"  then Slicers::OrcaSlicer.new  # Use OrcaSlicer for all (PrusaSlicer removed)
    when "bambu_studio"  then Slicers::OrcaSlicer.new
    else raise "Unknown slicer: #{slicer_name}"
    end
  end
end
