from emit_releases_file import write_releases_dictionary_to_bash

import os
import mock
from mock import mock_open
from six import PY2

import pytest

if PY2:
    BUILTINS_OPEN = "__builtin__.open"
else:
    BUILTINS_OPEN = "builtins.open"


def test_empty_relases_dictionary_fails():
    assert (not write_releases_dictionary_to_bash({}, ""))


@pytest.fixture
def releases_dictionary():
    return {
        'undercloud_install_release': 'queens',
        'undercloud_install_hash': 'current-tripleo',
        'undercloud_target_release': 'master',
        'undercloud_target_hash': 'current-tripleo',
        'overcloud_deploy_release': 'master',
        'overcloud_deploy_hash': 'current-tripleo',
        'overcloud_target_release': 'master',
        'overcloud_target_hash': 'current-tripleo',
    }


@pytest.mark.parametrize('deleted_key', [
    'undercloud_install_release',
    'undercloud_install_hash',
    'undercloud_target_release',
    'undercloud_target_hash',
    'overcloud_deploy_release',
    'overcloud_deploy_hash',
    'overcloud_target_release',
    'overcloud_target_hash',
])
def test_missing_key_fails(releases_dictionary, deleted_key):
    wrong_releases_dictionary = releases_dictionary.pop(deleted_key)
    assert (not write_releases_dictionary_to_bash(wrong_releases_dictionary,
                                                  ""))


@mock.patch(BUILTINS_OPEN, new_callable=mock_open)
def test_open_exception_fails(mock, releases_dictionary):
    bash_script = '/foo/bar.sh'
    mock.side_effect = IOError
    assert (not write_releases_dictionary_to_bash(releases_dictionary,
                                                  bash_script))


@mock.patch(BUILTINS_OPEN, new_callable=mock_open)
def test_output_is_sourceable(mock, releases_dictionary):
    bash_script = '/foo/bar.sh'
    assert (write_releases_dictionary_to_bash(releases_dictionary,
                                              bash_script))
    mock.assert_called_once_with(bash_script, 'w')
    handle = mock()
    args, _ = handle.write.call_args
    written_content = args[0]
    # TODO: check environment variables
    assert (0 == os.system(written_content))
