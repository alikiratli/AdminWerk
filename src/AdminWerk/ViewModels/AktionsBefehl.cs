using System.Windows.Input;

namespace AdminWerk.ViewModels;

/// <summary>Einfache ICommand-Implementierung (RelayCommand) fuer Schaltflaechen.</summary>
public sealed class AktionsBefehl : ICommand
{
    private readonly Action<object?> _ausfuehren;
    private readonly Func<object?, bool>? _kannAusfuehren;

    public AktionsBefehl(Action<object?> ausfuehren, Func<object?, bool>? kannAusfuehren = null)
    {
        _ausfuehren = ausfuehren ?? throw new ArgumentNullException(nameof(ausfuehren));
        _kannAusfuehren = kannAusfuehren;
    }

    public event EventHandler? CanExecuteChanged
    {
        add => CommandManager.RequerySuggested += value;
        remove => CommandManager.RequerySuggested -= value;
    }

    public bool CanExecute(object? parameter) => _kannAusfuehren?.Invoke(parameter) ?? true;

    public void Execute(object? parameter) => _ausfuehren(parameter);
}
