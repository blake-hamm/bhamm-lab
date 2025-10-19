import os
import sys
import yaml
import hashlib
import logging
import shutil
from pathlib import Path
from huggingface_hub import hf_hub_download
from huggingface_hub.utils import enable_progress_bars


logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)],
)


MODELS_DIR = Path(os.getenv("MODELS_DIR", "/models"))
CONFIG_FILE = Path(os.getenv("CONFIG_FILE", "/config/models.yaml"))


def download_model(model: dict) -> bool:
    """Download a single model based on the provided configuration."""
    try:
        repo_id = model["repo_id"]
        filename = model["filename"]
        revision = model.get("revision", "main")
    except KeyError as e:
        logging.error(f"Skipping model due to missing required key: {e}")
        return False

    filepath = MODELS_DIR / filename
    logging.info(f"Processing model: {repo_id}/{filename}")

    if filepath.exists() and filepath.is_file():
        file_size = filepath.stat().st_size
        logging.info(f"File already exists: {filepath} ({file_size / (1024**3):.2f} GB)")
        return True

    logging.info(f"Downloading from repo '{repo_id}' (revision: {revision})")
    try:
        # Download to HuggingFace cache (creates symlink)
        cached_path = hf_hub_download(
            repo_id=repo_id,
            filename=filename,
            revision=revision,
            local_dir=str(MODELS_DIR),
        )

        logging.info(f"Download complete: {cached_path}")

        final_path = MODELS_DIR / filename
        if not final_path.exists():
            logging.error(f"Expected file not found at {final_path}")
            return False

        file_size = final_path.stat().st_size
        logging.info(f"Model ready: {final_path} ({file_size / (1024**3):.2f} GB)")

        return True

    except Exception as e:
        logging.error(f"Download failed: {e}")
        if filepath.exists():
            filepath.unlink()
        return False


def main():
    """Main entrypoint."""
    MODELS_DIR.mkdir(parents=True, exist_ok=True)

    if not CONFIG_FILE.is_file():
        logging.critical(f"Config file not found at {CONFIG_FILE}")
        sys.exit(1)

    logging.info(f"Loading model configuration from: {CONFIG_FILE}")
    with open(CONFIG_FILE, "r") as f:
        config = yaml.safe_load(f)

    models = config.get("models", [])
    if not models:
        logging.warning("No models found in configuration. Exiting.")
        return

    logging.info(f"Found {len(models)} models in configuration.")
    results = [download_model(model) for model in models]

    success_count = sum(results)
    failure_count = len(results) - success_count
    logging.info(f"Download summary: {success_count} successful, {failure_count} failed.")

    if failure_count > 0:
        logging.error("One or more model downloads failed.")
        sys.exit(1)

    logging.info("All models are ready!")

    logging.info("=== Final model inventory ===")
    for model_file in sorted(MODELS_DIR.glob("*.gguf")):
        size_gb = model_file.stat().st_size / (1024**3)
        logging.info(f"  ✓ {model_file.name} ({size_gb:.2f} GB)")


if __name__ == "__main__":
    enable_progress_bars()
    main()
