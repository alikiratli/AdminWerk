using System.Globalization;
using System.Windows;
using System.Windows.Markup;

namespace AdminWerk;

public partial class App : Application
{
    protected override void OnStartup(StartupEventArgs e)
    {
        // Oberflaeche und Formatierungen konsequent auf Deutsch.
        var kultur = new CultureInfo("de-DE");
        CultureInfo.DefaultThreadCurrentCulture = kultur;
        CultureInfo.DefaultThreadCurrentUICulture = kultur;

        FrameworkElement.LanguageProperty.OverrideMetadata(
            typeof(FrameworkElement),
            new FrameworkPropertyMetadata(XmlLanguage.GetLanguage(kultur.IetfLanguageTag)));

        base.OnStartup(e);
    }
}
