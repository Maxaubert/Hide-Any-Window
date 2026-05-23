using System;
using System.IO;
using System.Threading.Tasks;
using HideAnyWindowManager.Models;
using HideAnyWindowManager.Services;
using Xunit;

public class ConfigStoreDurabilityTests
{
    private static string TempPath()
        => Path.Combine(Path.GetTempPath(), $"haw-dur-{Guid.NewGuid():N}.json");

    [Fact]
    public async Task CorruptFileIsBackedUpAndDefaultsReturned()
    {
        var path = TempPath();
        var backup = Path.Combine(
            Path.GetDirectoryName(path)!,
            Path.GetFileNameWithoutExtension(path) + ".corrupt.json");
        try
        {
            await File.WriteAllTextAsync(path, "{ this is not valid json ");
            var store = new ConfigStore(path);

            var loaded = await store.LoadAsync();

            // Falls back to defaults rather than throwing...
            Assert.Equal("running", loaded.ServiceState);
            Assert.Empty(loaded.Rules);
            // ...and the unparseable file is preserved for hand-recovery.
            Assert.True(File.Exists(backup), "corrupt config should be backed up");
            Assert.Contains("not valid json", await File.ReadAllTextAsync(backup));
        }
        finally
        {
            File.Delete(path);
            File.Delete(backup);
        }
    }

    [Fact]
    public async Task CorruptBackupIsNotClobberedOnRepeatedLoads()
    {
        var path = TempPath();
        var backup = Path.Combine(
            Path.GetDirectoryName(path)!,
            Path.GetFileNameWithoutExtension(path) + ".corrupt.json");
        try
        {
            await File.WriteAllTextAsync(path, "first-garbage");
            var store = new ConfigStore(path);
            await store.LoadAsync();                       // creates backup with "first-garbage"

            await File.WriteAllTextAsync(path, "second-garbage");
            await store.LoadAsync();                       // must NOT overwrite the first snapshot

            Assert.Equal("first-garbage", await File.ReadAllTextAsync(backup));
        }
        finally
        {
            File.Delete(path);
            File.Delete(backup);
        }
    }

    [Fact]
    public async Task FlushPendingWritesDebouncedSave()
    {
        var path = TempPath();
        try
        {
            var store = new ConfigStore(path);
            var cfg = new Config
            {
                ServiceState = "stopped",
                Rules = { new Rule { Id = "magnify-exe", Exe = "magnify.exe", Enabled = true } },
            };

            store.ScheduleSave(cfg);     // would otherwise wait 200ms
            await store.FlushPendingAsync();   // forces it now

            Assert.True(File.Exists(path), "flush should have written the file immediately");
            var loaded = await store.LoadAsync();
            Assert.Equal("stopped", loaded.ServiceState);
            Assert.Single(loaded.Rules);
        }
        finally
        {
            File.Delete(path);
        }
    }

    [Fact]
    public async Task FlushPendingIsNoOpWhenNothingScheduled()
    {
        var path = TempPath();
        try
        {
            var store = new ConfigStore(path);
            await store.FlushPendingAsync();          // nothing scheduled
            Assert.False(File.Exists(path), "flush with no pending save should not create a file");
        }
        finally
        {
            if (File.Exists(path)) File.Delete(path);
        }
    }

    [Fact]
    public async Task LastScheduledSaveWins()
    {
        var path = TempPath();
        try
        {
            var store = new ConfigStore(path);
            store.ScheduleSave(new Config { ServiceState = "running" });
            store.ScheduleSave(new Config { ServiceState = "stopped" });   // supersedes
            await store.FlushPendingAsync();

            var loaded = await store.LoadAsync();
            Assert.Equal("stopped", loaded.ServiceState);
        }
        finally
        {
            File.Delete(path);
        }
    }
}
