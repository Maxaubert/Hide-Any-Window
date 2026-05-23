using System;
using System.Threading;
using HideAnyWindowManager.Services;
using Xunit;

public class ServiceControllerTests
{
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
