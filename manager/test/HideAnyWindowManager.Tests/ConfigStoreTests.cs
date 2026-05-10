using System.IO;
using System.Threading.Tasks;
using HideAnyWindowManager.Models;
using HideAnyWindowManager.Services;
using Xunit;

public class ConfigStoreTests
{
    [Fact]
    public async Task RoundTripsConfigToDisk()
    {
        var path = Path.Combine(Path.GetTempPath(), $"haw-test-{System.Guid.NewGuid():N}.json");
        var store = new ConfigStore(path);

        var cfg = new Config
        {
            ServiceState = "stopped",
            Rules = { new Rule { Id = "magnify-exe", Exe = "magnify.exe", Name = "Magnifier", Enabled = true } }
        };
        await store.SaveImmediateAsync(cfg);

        var loaded = await store.LoadAsync();
        Assert.Equal("stopped", loaded.ServiceState);
        Assert.Single(loaded.Rules);
        Assert.Equal("magnify.exe", loaded.Rules[0].Exe);
        Assert.True(loaded.Rules[0].Enabled);

        File.Delete(path);
    }

    [Fact]
    public async Task ReturnsDefaultsWhenFileMissing()
    {
        var path = Path.Combine(Path.GetTempPath(), $"haw-missing-{System.Guid.NewGuid():N}.json");
        var store = new ConfigStore(path);

        var loaded = await store.LoadAsync();
        Assert.Equal("running", loaded.ServiceState);
        Assert.Empty(loaded.Rules);
    }
}
