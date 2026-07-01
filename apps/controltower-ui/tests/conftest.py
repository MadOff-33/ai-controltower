import importlib.util
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]
APP_PATH = ROOT / "apps" / "controltower-ui" / "app.py"


def _load_app_module():
    spec = importlib.util.spec_from_file_location("controltower_ui_app", APP_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@pytest.fixture(scope="session")
def app_module():
    return _load_app_module()


@pytest.fixture
def client(app_module):
    app = app_module.create_app(str(ROOT))
    return app.test_client()
