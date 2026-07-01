import sys

ACCENTED_TEXT = "Créer é è à ç œ"


def test_read_json_process_decodes_utf8_accents(app_module):
    child_script = (
        "import sys, json\n"
        "data = json.dumps({'msg': 'Créer é è à ç œ'})\n"
        "sys.stdout.buffer.write(data.encode('utf-8'))\n"
    )
    command = [sys.executable, "-c", child_script]

    result = app_module.read_json_process(command)

    assert result["msg"] == ACCENTED_TEXT
    assert not any(marker in result["msg"] for marker in app_module.MOJIBAKE_MARKERS)
