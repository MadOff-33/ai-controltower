using System;
using System.Diagnostics;
using System.IO;

namespace AIControlTower
{
    public static class ControlTowerLauncher
    {
        [STAThread]
        public static int Main(string[] args)
        {
            string root = @"C:\AI_ControlTower";
            string launcher = Path.Combine(root, "apps", "controltower-ui", "ControlTower.cmd");
            if (!File.Exists(launcher))
            {
                Console.Error.WriteLine("ControlTower launcher introuvable: " + launcher);
                return 1;
            }

            var startInfo = new ProcessStartInfo
            {
                FileName = launcher,
                WorkingDirectory = root,
                UseShellExecute = true,
                WindowStyle = ProcessWindowStyle.Normal
            };
            Process.Start(startInfo);
            return 0;
        }
    }
}
