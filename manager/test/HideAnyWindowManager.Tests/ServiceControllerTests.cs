using System;
using System.Threading;
using HideAnyWindowManager.Models;
using HideAnyWindowManager.Services;
using Xunit;

public class ServiceControllerTests
{
    [Theory]
    [InlineData("stopped", false)]
    [InlineData("STOPPED", false)]   // state comparison must be case-insensitive
    [InlineData("running", true)]
    [InlineData("", true)]           // unknown/absent state -> start (fail open)
    [InlineData("bogus", true)]
    public void ShouldStartAtLogon_HonoursServiceState(string state, bool expected)
    {
        var cfg = new Config { ServiceState = state };
        Assert.Equal(expected, ServiceController.ShouldStartAtLogon(cfg));
    }

    [Fact]
    public void ShouldStartAtLogon_NullConfigStarts()
    {
        // A missing/unreadable config must not silently disable autostart.
        Assert.True(ServiceController.ShouldStartAtLogon(null));
    }


    [Fact]
    public void DetectsHeldMutex()
    {
        // Use a unique mutex name so the test is hermetic — it must pass whether or not
        // the real HideAnyWindowService is installed and running on this machine.
        var name = "HideAnyWindow_Test_" + Guid.NewGuid().ToString("N");
        var ctrl = new ServiceController(name);
        Assert.False(ctrl.IsServiceRunning());   // none held yet

        using var owned = new Mutex(initiallyOwned: false, name: name);
        Assert.True(ctrl.IsServiceRunning());
    }
}
