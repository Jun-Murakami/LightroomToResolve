import os
import sys
import json
import traceback
import subprocess
import platform


def log(message):
    print(f"[LightroomToResolve] {message}")


def get_queue_dir():
    if sys.platform.startswith("win"):
        base = os.path.join(os.environ.get("APPDATA", ""), "LightroomToResolve")
    elif sys.platform == "darwin":
        base = os.path.expanduser("~/Library/Application Support/LightroomToResolve")
    else:
        base = os.path.expanduser("~/.config/LightroomToResolve")
    queue = os.path.join(base, "queue")
    processed = os.path.join(base, "processed")
    os.makedirs(queue, exist_ok=True)
    os.makedirs(processed, exist_ok=True)
    return queue, processed


def get_resolve():
    try:
        import DaVinciResolveScript as dvr
    except ImportError:
        log(
            "DaVinciResolveScript is not available. Please run this script from Resolve."
        )
        return None
    resolve = dvr.scriptapp("Resolve")
    if not resolve:
        log("Cannot connect to Resolve. Is it running?")
    return resolve


def find_dng_converter():
    if sys.platform.startswith("win"):
        paths = [
            r"C:\Program Files\Adobe\Adobe DNG Converter\Adobe DNG Converter.exe",
            r"C:\Program Files (x86)\Adobe\Adobe DNG Converter\Adobe DNG Converter.exe",
        ]
    else:
        paths = [
            "/Applications/Adobe DNG Converter.app/Contents/MacOS/Adobe DNG Converter"
        ]

    for p in paths:
        if os.path.exists(p):
            return p
    return None


def convert_to_dng(raw_path, converter_path):
    if not os.path.exists(raw_path):
        log(f"RAW file not found: {raw_path}")
        return None

    source_dir = os.path.dirname(raw_path)
    base_name = os.path.splitext(os.path.basename(raw_path))[0]
    # Converter logic: outputs to same dir if -d is not set properly, or we set -d source_dir
    # We want output: source_dir/basename_2d.dng
    # Adobe DNG Converter CLI is a bit tricky.
    # Usage: -c (convert) -d <dest> -o <outname> <files> ...
    # Note: -o does NOT accept full path on some versions, only filename.

    # We'll output to source_dir and rename if needed
    # But to be safe against overwrite, we specify a temp name or check existing
    expected_dng = os.path.join(source_dir, f"{base_name}.dng")
    final_dng = os.path.join(source_dir, f"{base_name}_2d.dng")

    # Clean previous
    if os.path.exists(expected_dng):
        try:
            os.remove(expected_dng)
        except OSError:
            pass
    if os.path.exists(final_dng):
        try:
            os.remove(final_dng)
        except OSError:
            pass

    cmd = [
        converter_path,
        "-c",
        "-d",
        source_dir,
        # "-p1",  # Removed to match standard DNG behavior (keep preview)
        # "-l",   # Removed to avoid Linear DNG (keep Mosaic/RAW)
        # "-w",
        # "-e",
        raw_path,
    ]

    log(f"Converting: {raw_path} -> DNG")
    try:
        subprocess.run(cmd, check=True, capture_output=True)
    except subprocess.CalledProcessError as e:
        log(f"DNG Converter failed for {raw_path}: {e}")
        return None

    # Adobe DNG Converter usually creates {filename}.dng
    if os.path.exists(expected_dng):
        try:
            os.rename(expected_dng, final_dng)
            return final_dng
        except OSError as e:
            log(f"Failed to rename DNG: {e}")
            return expected_dng
    elif os.path.exists(final_dng):
        # In case we figured out how to output directly or it persisted
        return final_dng

    log(f"DNG not found after conversion: {expected_dng}")
    return None


def ensure_project(resolve):
    project_manager = resolve.GetProjectManager()
    if not project_manager:
        log("Failed to get Project Manager.")
        return None
    project = project_manager.GetCurrentProject()
    if not project:
        log("No project is currently open.")
        return None
    return project


def get_or_create_bin(media_pool, bin_path):
    folders = media_pool.GetRootFolder()
    current = folders
    media_pool.SetCurrentFolder(folders)
    parts = [part.strip() for part in bin_path.split("/") if part.strip()]
    for part in parts:
        found = None
        for child in current.GetSubFolderList():
            if child.GetName() == part:
                found = child
                break
        if found:
            current = found
        else:
            new_folder = media_pool.AddSubFolder(current, part)
            if not new_folder:
                raise RuntimeError(f"Failed to create folder: {part}")
            current = new_folder
    return current


def process_job(job_path, resolve):
    log(f"Processing {job_path}")
    with open(job_path, "r", encoding="utf-8") as f:
        job = json.load(f)

    project = ensure_project(resolve)
    if not project:
        return False

    media_pool = project.GetMediaPool()

    # Check source type and prepare import list
    source_type = job.get("sourceType", "TIFF")

    # Files list might contain objects now: {path, name, isVertical, orientation}
    job_files = job.get("files", [])
    input_files = []
    is_vertical_map = {}  # Path -> bool
    orientation_map = {}  # Path -> str

    for item in job_files:
        if isinstance(item, dict):
            path = item.get("path")
            is_vertical = item.get("isVertical", False)
            orientation = item.get("orientation")
        else:
            path = item
            is_vertical = False
            orientation = None

        if path:
            input_files.append(path)
            is_vertical_map[path] = is_vertical
            if orientation:
                orientation_map[path] = orientation

    # Set up Bins
    # 1. Timeline Bin (Collection Hierarchy under "Collections")
    # Create/Get "Collections" root bin first
    root_folder = media_pool.GetRootFolder()
    media_pool.SetCurrentFolder(root_folder)

    collections_root_bin = None
    for child in root_folder.GetSubFolderList():
        if child.GetName() == "Collections":
            collections_root_bin = child
            break
    if not collections_root_bin:
        collections_root_bin = media_pool.AddSubFolder(root_folder, "Collections")

    # Now create the hierarchy INSIDE "Collections"
    bin_path = job.get("binPath", "Lightroom Import")

    # Helper to get/create bin starting from a specific folder
    def get_or_create_bin_under(media_pool, start_folder, relative_path):
        current = start_folder
        parts = [part.strip() for part in relative_path.split("/") if part.strip()]
        for part in parts:
            found = None
            for child in current.GetSubFolderList():
                if child.GetName() == part:
                    found = child
                    break
            if found:
                current = found
            else:
                new_folder = media_pool.AddSubFolder(current, part)
                if not new_folder:
                    raise RuntimeError(f"Failed to create folder: {part}")
                current = new_folder
        return current

    timeline_bin = get_or_create_bin_under(media_pool, collections_root_bin, bin_path)

    # 2. Source Photos Bin
    # Determine sub-folder name from the first file's parent directory name
    source_parent_name = "Imported"
    if input_files:
        first_file = input_files[0]
        # If raw, we might use raw path, if tiff, tiff path.
        # Just take parent dir name of first input file.
        source_parent_name = os.path.basename(os.path.dirname(first_file))

    root_folder = media_pool.GetRootFolder()
    media_pool.SetCurrentFolder(root_folder)

    # Create/Get "Source Photos" root bin
    source_root_bin = None
    for child in root_folder.GetSubFolderList():
        if child.GetName() == "Source Photos":
            source_root_bin = child
            break
    if not source_root_bin:
        source_root_bin = media_pool.AddSubFolder(root_folder, "Source Photos")

    # Create/Get sub-bin for this batch (using parent folder name)
    media_pool.SetCurrentFolder(source_root_bin)
    source_bin = None
    for child in source_root_bin.GetSubFolderList():
        if child.GetName() == source_parent_name:
            source_bin = child
            break
    if not source_bin:
        source_bin = media_pool.AddSubFolder(source_root_bin, source_parent_name)

    # Set current folder to Source Bin for import
    media_pool.SetCurrentFolder(source_bin)

    import_files = []

    if source_type == "RAW":
        converter = find_dng_converter()
        if not converter:
            log("Adobe DNG Converter not found. Cannot process RAW files.")
            return False

        # Common non-RAW extensions to skip just in case
        SKIP_EXTS = {".jpg", ".jpeg", ".png", ".tif", ".tiff", ".psd", ".mp4", ".mov"}

        for raw_path in input_files:
            base, ext = os.path.splitext(raw_path)
            if ext.lower() in SKIP_EXTS:
                log(f"Skipping non-RAW file in RAW job: {raw_path}")
                continue

            dng_path = convert_to_dng(raw_path, converter)
            if dng_path:
                import_files.append(dng_path)
                # Map vertical/orientation status to new DNG path
                if is_vertical_map.get(raw_path):
                    is_vertical_map[dng_path] = True
                if orientation_map.get(raw_path):
                    orientation_map[dng_path] = orientation_map[raw_path]
            else:
                log(f"Skipping {raw_path} due to conversion failure")
    else:
        import_files = input_files

    if not import_files:
        log("No files to import.")
        return False

    imported = media_pool.ImportMedia(import_files)
    if not imported:
        log("ImportMedia returned empty list (or failed).")
        return False

    # Process each clip to create individual timelines
    timelines_created = 0

    for clip in imported:
        # Switch context to Timeline Bin for timeline creation
        media_pool.SetCurrentFolder(timeline_bin)

        file_path = clip.GetClipProperty("File Path")

        is_vertical = False
        # Exact match try
        if file_path in is_vertical_map:
            is_vertical = is_vertical_map[file_path]
        else:
            # Fallback search
            fname = os.path.basename(file_path)
            for k, v in is_vertical_map.items():
                if os.path.basename(k) == fname:
                    is_vertical = v
                    break

        # Get clip resolution to set timeline resolution
        # Resolution string is usually "Width x Height" (e.g. "6000x4000")
        res_str = clip.GetClipProperty("Resolution")
        try:
            w_str, h_str = res_str.split("x")
            clip_w = int(w_str)
            clip_h = int(h_str)
        except ValueError:
            log(f"Failed to parse resolution: {res_str}. Using defaults.")
            clip_w = 1920
            clip_h = 1080

        # Determine timeline resolution based on is_vertical
        # If DNG is 6000x4000 but vertical, we want 4000x6000 timeline
        # If clip is already vertical in resolution (rare for DNG without rotation), handle that

        if is_vertical:
            # Force vertical orientation (Short x Long)
            tl_w = min(clip_w, clip_h)
            tl_h = max(clip_w, clip_h)
        else:
            # Force horizontal orientation (Long x Short)
            tl_w = max(clip_w, clip_h)
            tl_h = min(clip_w, clip_h)

        clip_name = clip.GetName()
        base_name = os.path.splitext(clip_name)[0]

        # Create EMPTY timeline first to set settings
        new_timeline = media_pool.CreateEmptyTimeline(base_name)

        if new_timeline:
            timelines_created += 1
            log(f"Created timeline: {new_timeline.GetName()}")

            # Enable custom settings
            new_timeline.SetSetting("useCustomSettings", "1")

            # Set Resolution
            new_timeline.SetSetting("timelineResolutionWidth", str(tl_w))
            new_timeline.SetSetting("timelineResolutionHeight", str(tl_h))
            new_timeline.SetSetting("timelineOutputResolutionWidth", str(tl_w))
            new_timeline.SetSetting("timelineOutputResolutionHeight", str(tl_h))

            # Add clip to timeline
            media_pool.AppendToTimeline(clip)

            # Rotate clip if needed based on orientation
            # Get the clip we just added (it's the only item on V1)
            items = new_timeline.GetItemListInTrack("video", 1)
            if items:
                item = items[0]
                # Check orientation map
                orientation = None
                # Find orientation for this clip path
                if file_path in orientation_map:
                    orientation = orientation_map[file_path]
                else:
                    fname = os.path.basename(file_path)
                    for k, v in orientation_map.items():
                        if os.path.basename(k) == fname:
                            orientation = v
                            break

                # Apply rotation based on orientation tag
                # "BC" = Rotated 90 CW (Right) -> Needs -90 (270) correction?
                # Or if it's displayed sideways (top is left), we rotate 90 (Right).
                # Let's assume simple case: if is_vertical is true but image is sideways, rotate 90 or 270.
                # Usually vertical shot displayed horizontally needs +/-90 rotation.

                rotation_angle = 0.0
                if orientation == "BC":  # Right, Top -> 90 CW
                    rotation_angle = -90.0  # Or 270.0
                elif orientation == "DA":  # Left, Bottom -> 90 CCW
                    rotation_angle = 90.0
                elif orientation == "CD":  # Bottom, Right -> 180
                    rotation_angle = 180.0
                elif is_vertical and tl_w < tl_h:
                    # Fallback: if vertical flag is set but we don't have specific orientation tag (or it's generic),
                    # and we made a vertical timeline, force a rotation if the image aspect doesn't match.
                    # However, we already swapped resolution. If the image itself is unrotated DNG (landscape pixels),
                    # we MUST rotate it to fill the vertical timeline.
                    # Assume 90 degrees clockwise (standard portrait grip)
                    if clip_w > clip_h:  # Image pixels are landscape
                        rotation_angle = -90.0  # Rotate to vertical

                if rotation_angle != 0.0:
                    item.SetProperty("RotationAngle", rotation_angle)
                    log(f" -> Applied rotation: {rotation_angle}")

                    # Fix scaling after rotation to fill frame
                    # If rotated to vertical in a vertical timeline, we need to zoom to fill
                    scale_factor = max(clip_w, clip_h) / min(clip_w, clip_h)
                    item.SetProperty("ZoomX", scale_factor)
                    item.SetProperty("ZoomY", scale_factor)
                    log(f" -> Applied Zoom: {scale_factor}")

            log(f" -> Set resolution to {tl_w}x{tl_h}")
        else:
            log(f"Failed to create timeline for {clip_name}")

    if timelines_created > 0:
        return True
    else:
        log("No timelines were created.")
        return False


def main():
    queue_dir, processed_dir = get_queue_dir()
    resolve = get_resolve()
    if not resolve:
        return

    job_files = sorted(
        [f for f in os.listdir(queue_dir) if f.endswith(".json")],
        key=lambda name: os.path.getmtime(os.path.join(queue_dir, name)),
    )

    if not job_files:
        log("Queue is empty.")
        return

    for file_name in job_files:
        job_path = os.path.join(queue_dir, file_name)
        try:
            if process_job(job_path, resolve):
                processed_path = os.path.join(processed_dir, file_name)
                os.replace(job_path, processed_path)
                log(f"Job completed: {file_name}")
            else:
                log(f"Job failed: {file_name}")
        except Exception as exc:
            log(f"Error processing {file_name}: {exc}")
            log(traceback.format_exc())


if __name__ == "__main__":
    main()
