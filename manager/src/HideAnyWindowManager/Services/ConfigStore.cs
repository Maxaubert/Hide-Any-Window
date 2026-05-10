using System;
using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading;
using System.Threading.Tasks;
using HideAnyWindowManager.Models;

namespace HideAnyWindowManager.Services;

public sealed class ConfigStore
{
    private static readonly JsonSerializerOptions JsonOpts = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.Never,
    };

    private readonly string _path;
    private readonly SemaphoreSlim _writeLock = new(1, 1);
    private CancellationTokenSource? _debounceCts;

    public string ConfigPath => _path;

    public ConfigStore() : this(DefaultPath()) { }
    public ConfigStore(string path) { _path = path; }

    public static string DefaultPath()
        => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                        "HideAnyWindow", "config.json");

    public async Task<Config> LoadAsync()
    {
        if (!File.Exists(_path))
            return new Config();
        try
        {
            await using var fs = File.OpenRead(_path);
            var cfg = await JsonSerializer.DeserializeAsync<Config>(fs, JsonOpts);
            return cfg ?? new Config();
        }
        catch (JsonException)
        {
            return new Config();   // malformed -> caller can decide whether to overwrite
        }
    }

    /// <summary>Schedules a save for 200ms after the last call. Subsequent calls cancel the prior schedule.</summary>
    public void ScheduleSave(Config cfg)
    {
        _debounceCts?.Cancel();
        _debounceCts = new CancellationTokenSource();
        var token = _debounceCts.Token;
        _ = Task.Run(async () =>
        {
            try
            {
                await Task.Delay(200, token);
                await SaveImmediateAsync(cfg);
            }
            catch (TaskCanceledException) { /* superseded */ }
        });
    }

    public async Task SaveImmediateAsync(Config cfg)
    {
        await _writeLock.WaitAsync();
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
            var tmp = _path + ".tmp";
            await using (var fs = File.Create(tmp))
                await JsonSerializer.SerializeAsync(fs, cfg, JsonOpts);
            // File.Move with overwrite=true is atomic on the same volume.
            File.Move(tmp, _path, overwrite: true);
        }
        finally
        {
            _writeLock.Release();
        }
    }
}
