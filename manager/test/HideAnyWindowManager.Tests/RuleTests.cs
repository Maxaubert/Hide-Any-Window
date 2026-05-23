using HideAnyWindowManager.Models;
using Xunit;

public class RuleTests
{
    [Theory]
    [InlineData("magnify.exe", "magnify-exe")]
    [InlineData("Magnify.EXE", "magnify-exe")]     // lower-cased
    [InlineData("notepad.exe", "notepad-exe")]
    public void IdFromExe_NormalizesToStableLowercaseId(string exe, string expected)
    {
        Assert.Equal(expected, Rule.IdFromExe(exe));
    }

    [Fact]
    public void IdFromExe_IsStableAcrossCalls()
    {
        Assert.Equal(Rule.IdFromExe("foo.exe"), Rule.IdFromExe("FOO.exe"));
    }
}
