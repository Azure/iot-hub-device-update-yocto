# -------------------------------------------------------------------------
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License. See License.txt in the project root for
# license information.
# --------------------------------------------------------------------------
import io
import sys
import time
import unittest
import xmlrunner
from xmlrunner.extra.xunit_plugin import transform
# Note: the intention is that this script is called like:
# python ./scenarios/<scenario-name>/testscript.py
sys.path.append('./scripts/')
from testingtoolkit import DeviceUpdateTestHelper
from testingtoolkit import UpdateId
from testingtoolkit import DeploymentStatusResponse
from testingtoolkit import DuAutomatedTestConfigurationManager


class CreateUpdateTest(unittest.TestCase):

    def test_CreateAndImportUpdate(self):
        self.aduTestConfig = DuAutomatedTestConfigurationManager.FromOSEnvironment()
        self.duTestHelper = self.aduTestConfig.CreateDeviceUpdateTestHelper()

        #
        # Steps
        #
        success = self.duTestHelper.CreateUpdateManifest()
        self.assertTrue(success)


if (__name__ == "__main__"):
    out = io.BytesIO()

    unittest.main(testRunner = xmlrunner.XMLTestRunner(output=out), failfast=False, buffer=False, catchbreak=False, exit=False)

    with open('./testresults/create-update-manifest.xml', 'wb') as report:
        report.write(transform(out.getvalue()))
