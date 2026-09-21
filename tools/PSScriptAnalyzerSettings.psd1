<#
    Regelwerk fuer PSScriptAnalyzer im AdminWerk-Skriptkatalog.

    Jede Ausnahme steht hier mit Begruendung. Was nicht ausgenommen ist, muss sauber
    sein - der CI-Schritt bricht sonst ab. Neue Ausnahmen bitte nur mit Begruendung
    ergaenzen, sonst verliert die Pruefung ihren Wert.
#>
@{
    Severity = @('Error', 'Warning')

    ExcludeRules = @(
        # Die Skripte sind Konsolenwerkzeuge fuer Administratoren. Die farbige,
        # formatierte Ausgabe ist nicht Nebensache, sondern das Ergebnis. Wo ein
        # Objekt gebraucht wird, geben die Skripte zusaetzlich PSCustomObject aus.
        'PSAvoidUsingWriteHost',

        # Trifft auf Parameter zu, die nur in einer verschachtelten Funktion gelesen
        # werden (z. B. $LogDatei in dienste-ueberwachen.ps1). PowerShell loest das
        # ueber den Gueltigkeitsbereich auf; die Regel sieht es nicht.
        'PSReviewUnusedParameter',

        # Hier ist die Voreinstellung $true jeweils die sichere Variante
        # (Kennwortwechsel erzwingen, leere Gruppen ausblenden). Die Konvention des
        # Projekts lautet: der gefaehrliche Fall braucht die zusaetzliche Eingabe.
        'PSAvoidDefaultValueSwitchParameter',

        # New-Kennwort erzeugt nur eine Zeichenfolge und veraendert nichts. Der
        # Namenspraefix loest die Regel aus, nicht das Verhalten.
        'PSUseShouldProcessForStateChangingFunctions',

        # Beim Anlegen eines Kontos mit erzeugtem Kennwort fuehrt kein Weg daran
        # vorbei. Das Kennwort steht nur im Arbeitsspeicher und auf dem Bildschirm,
        # nie in einer Datei - siehe Konvention im Katalog.
        'PSAvoidUsingConvertToSecureStringWithPlainText'
    )
}
