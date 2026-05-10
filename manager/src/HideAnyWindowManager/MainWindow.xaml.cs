using HideAnyWindowManager.ViewModels;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace HideAnyWindowManager;

public sealed partial class MainWindow : Window
{
    public MainViewModel ViewModel { get; } = new();

    public MainWindow()
    {
        InitializeComponent();
        RulesList.ItemsSource = ViewModel.Rules;
    }

    // Wired up properly in Task 7
    private void AddButton_Click(object sender, RoutedEventArgs e) { }
    private void RemoveButton_Click(object sender, RoutedEventArgs e) { }
    private void RulesList_SelectionChanged(object sender, SelectionChangedEventArgs e) { }
    private void RuleToggle_Toggled(object sender, RoutedEventArgs e) { }
    private void ServiceButton_Click(object sender, RoutedEventArgs e) { }
}
