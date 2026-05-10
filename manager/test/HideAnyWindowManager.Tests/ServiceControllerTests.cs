using System.Threading;
using HideAnyWindowManager.Services;
using Xunit;

public class ServiceControllerTests
{
    [Fact]
    public void DetectsHeldMutex()
    {
        var ctrl = new ServiceController();
        Assert.False(ctrl.IsServiceRunning());   // none held yet

        using var owned = new Mutex(initiallyOwned: false, name: "HideAnyWindow_Service_Running");
        Assert.True(ctrl.IsServiceRunning());
    }
}
