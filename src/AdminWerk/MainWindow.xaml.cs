using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Input;

namespace AdminWerk;

public partial class MainWindow : Window
{
    public MainWindow() => InitializeComponent();

    // Strg+F: ins Suchfeld, den bisherigen Begriff markiert - wer tippt, ersetzt ihn.
    private void SuchfeldAnsteuern(object sender, ExecutedRoutedEventArgs e)
    {
        Suchfeld.Focus();
        Suchfeld.SelectAll();
    }

    // Eingabe oder Pfeil nach unten: vom Suchfeld in die Trefferliste, auf den
    // gewaehlten Treffer. Von dort geht es mit den Pfeiltasten weiter.
    private void Suchfeld_PreviewKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key is not (Key.Enter or Key.Down))
        {
            return;
        }

        // Die Bindung wartet 120 ms. Wer schnell tippt und gleich Eingabe drueckt,
        // soll trotzdem in der gefilterten Liste landen, nicht in der alten.
        BindingOperations.GetBindingExpression(Suchfeld, TextBox.TextProperty)?.UpdateSource();

        if (Skriptliste.Items.Count == 0)
        {
            return;
        }

        if (Skriptliste.SelectedIndex < 0)
        {
            Skriptliste.SelectedIndex = 0;
        }

        Skriptliste.UpdateLayout();
        Skriptliste.ScrollIntoView(Skriptliste.SelectedItem);
        if (Skriptliste.ItemContainerGenerator.ContainerFromIndex(Skriptliste.SelectedIndex) is ListBoxItem eintrag)
        {
            eintrag.Focus();
            e.Handled = true;
        }
    }
}
