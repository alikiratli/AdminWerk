using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace AdminWerk.ViewModels;

/// <summary>Minimale INotifyPropertyChanged-Basis fuer alle ViewModels.</summary>
public abstract class ViewModelBasis : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;

    protected void BenachrichtigeAenderung([CallerMemberName] string? eigenschaft = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(eigenschaft));

    protected bool SetzeFeld<T>(ref T feld, T wert, [CallerMemberName] string? eigenschaft = null)
    {
        if (EqualityComparer<T>.Default.Equals(feld, wert))
        {
            return false;
        }

        feld = wert;
        BenachrichtigeAenderung(eigenschaft);
        return true;
    }
}
