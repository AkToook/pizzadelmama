# AUTO-PRINTER — New Pizza Reims
# Double-cliquez sur LANCER-IMPRESSION.bat pour demarrer
# Ctrl+C pour arreter

$PROJECT_ID = 'pizza-reims'
$API_KEY = 'AIzaSyBc4KLK4E6p5rEmQBcdghX2YesveHyT2NU'
$POLL_INTERVAL = 10
$PRINTED_FILE = Join-Path $PSScriptRoot '.printed-orders.json'

$printedOrders = @{}
if (Test-Path $PRINTED_FILE) {
    try {
        $data = Get-Content $PRINTED_FILE -Raw | ConvertFrom-Json
        foreach ($id in $data) { $printedOrders[$id] = $true }
        Write-Host "Charge $($printedOrders.Count) commandes deja imprimees" -ForegroundColor Gray
    } catch {}
}

function Save-Printed {
    $printedOrders.Keys | ConvertTo-Json | Set-Content $PRINTED_FILE -Encoding UTF8
}

function Build-Ticket($order) {
    $ESC = [char]0x1B
    $GS = [char]0x1D
    $t = "${ESC}@"
    $t += "${ESC}E$([char]1)"
    $t += "${ESC}G$([char]1)"
    $t += "${ESC}a$([char]1)"
    $t += "${ESC}!$([char]0x30)"
    $t += "NEW PIZZA REIMS`n"
    $t += "${ESC}!$([char]0)"
    $t += "41 rue du Mont d'Arene`n"
    $t += "Tel: 03 26 04 30 51`n"
    $t += "================================`n"
    $t += "${ESC}a$([char]0)"
    $num = if ($order.orderNum) { $order.orderNum } else { '---' }
    $timeStr = '--:--'
    if ($order.createdAt) {
        try {
            $dt = [DateTime]::Parse($order.createdAt)
            $timeStr = $dt.ToString('HH:mm')
        } catch {}
    }
    $t += "${ESC}!$([char]0x30)"
    $t += "N. $num`n"
    $t += "${ESC}!$([char]0)"
    $t += "Heure: $timeStr`n"
    $t += "================================`n"
    $mode = if ($order.deliveryMode -eq 'livraison') { 'LIVRAISON' } else { 'A EMPORTER' }
    $t += "Mode  : $mode`n"
    $t += "Client: $($order.customerName)`n"
    $t += "Tel   : $($order.customerPhone)`n"
    if ($order.deliveryMode -eq 'livraison' -and $order.address) {
        $t += "Adresse: $($order.address)`n"
    }
    $t += "================================`n"
    foreach ($item in $order.items) {
        $price = [math]::Round([double]$item.price, 2)
        $t += "$($item.name)  ${price}EUR`n"
        if ($item.details) { $t += "  > $($item.details)`n" }
    }
    $t += "================================`n"
    $t += "${ESC}a$([char]1)"
    $t += "${ESC}!$([char]0x30)"
    $total = [math]::Round([double]$order.total, 2)
    $t += "TOTAL: ${total} EUR`n"
    $t += "${ESC}!$([char]0)"
    $pay = if ($order.status -eq 'PAYED_CASH') { 'ESPECES' } else { 'CARTE' }
    $t += "Paiement: $pay`n"
    if ($order.special) {
        $t += "================================`n"
        $t += "${ESC}a$([char]0)"
        $t += "NOTE: $($order.special)`n"
    }
    $t += "================================`n"
    $t += "${ESC}a$([char]1)"
    $t += "Merci de votre commande !`n"
    $t += "New Pizza Reims - 7j/7`n"
    $t += "`n`n`n`n"
    $t += "${GS}V$([char]0x42)$([char]0)"
    return $t
}

Add-Type @'
using System;
using System.Runtime.InteropServices;

public class RawPrinter {
    [StructLayout(LayoutKind.Sequential)] public struct DOCINFOA {
        [MarshalAs(UnmanagedType.LPStr)] public string pDocName;
        [MarshalAs(UnmanagedType.LPStr)] public string pOutputFile;
        [MarshalAs(UnmanagedType.LPStr)] public string pDatatype;
    }
    [DllImport("winspool.drv", SetLastError=true, CharSet=CharSet.Ansi)]
    public static extern bool OpenPrinter(string szPrinter, out IntPtr hPrinter, IntPtr pd);
    [DllImport("winspool.drv", SetLastError=true, CharSet=CharSet.Ansi)]
    public static extern bool StartDocPrinter(IntPtr hPrinter, int level, ref DOCINFOA di);
    [DllImport("winspool.drv", SetLastError=true)]
    public static extern bool StartPagePrinter(IntPtr hPrinter);
    [DllImport("winspool.drv", SetLastError=true)]
    public static extern bool WritePrinter(IntPtr hPrinter, IntPtr pBytes, int dwCount, out int dwWritten);
    [DllImport("winspool.drv", SetLastError=true)]
    public static extern bool EndPagePrinter(IntPtr hPrinter);
    [DllImport("winspool.drv", SetLastError=true)]
    public static extern bool EndDocPrinter(IntPtr hPrinter);
    [DllImport("winspool.drv", SetLastError=true)]
    public static extern bool ClosePrinter(IntPtr hPrinter);

    public static bool SendRaw(string printerName, byte[] data) {
        IntPtr hPrinter;
        if (!OpenPrinter(printerName, out hPrinter, IntPtr.Zero)) return false;
        var di = new DOCINFOA { pDocName = "Ticket", pDatatype = "RAW" };
        try {
            StartDocPrinter(hPrinter, 1, ref di);
            StartPagePrinter(hPrinter);
            IntPtr pBytes = Marshal.AllocCoTaskMem(data.Length);
            Marshal.Copy(data, 0, pBytes, data.Length);
            int written;
            bool ok = WritePrinter(hPrinter, pBytes, data.Length, out written);
            Marshal.FreeCoTaskMem(pBytes);
            EndPagePrinter(hPrinter);
            EndDocPrinter(hPrinter);
            return ok && written > 0;
        } finally {
            ClosePrinter(hPrinter);
        }
    }
}
'@ -ErrorAction SilentlyContinue

function Send-ToPrinter($printerName, $rawBytes) {
    for ($attempt = 1; $attempt -le 5; $attempt++) {
        try {
            $ok = [RawPrinter]::SendRaw($printerName, $rawBytes)
            if ($ok) {
                # Pause 3s pour laisser l'imprimante finir physiquement
                Start-Sleep -Seconds 3
                return $true
            }
        } catch {}
        Write-Host "  Tentative $attempt/5 echouee, pause 3s..." -ForegroundColor Yellow
        Start-Sleep -Seconds 3
    }
    return $false
}

function Print-Ticket($order, $docId) {
    $ticket = Build-Ticket $order
    $encoding = [System.Text.Encoding]::GetEncoding(437)
    $rawBytes = $encoding.GetBytes($ticket)
    $success = $false
    $printerName = $null

    # Trouver le nom de l'imprimante
    try {
        $default = (Get-CimInstance -ClassName Win32_Printer -Filter "Default=True")
        if ($default) {
            $printerName = $default.Name
        }
    } catch {}

    if (-not $printerName) {
        try {
            $xp = Get-CimInstance -ClassName Win32_Printer | Where-Object { $_.Name -like '*XP*80*' } | Select-Object -First 1
            if ($xp) { $printerName = $xp.Name }
        } catch {}
    }

    if ($printerName) {
        Write-Host "  Imprimante: $printerName" -ForegroundColor Cyan
        $success = Send-ToPrinter $printerName $rawBytes
        if ($success) {
            Write-Host "  Ticket imprime!" -ForegroundColor Green
        }
    }

    if ($success) {
        $printedOrders[$docId] = $true
        Save-Printed
        try {
            $url = "https://firestore.googleapis.com/v1/projects/$PROJECT_ID/databases/(default)/documents/orders/${docId}?updateMask.fieldPaths=printed&key=$API_KEY"
            $body = '{"fields":{"printed":{"booleanValue":true}}}'
            Invoke-RestMethod -Uri $url -Method Patch -Body $body -ContentType 'application/json' | Out-Null
            Write-Host "  Firebase: printed=true" -ForegroundColor Gray
        } catch {
            Write-Host "  WARN: Firebase update echoue: $_" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  ECHEC impression - sera retente au prochain cycle" -ForegroundColor Red
    }
}

function Check-Orders {
    try {
        $url = "https://firestore.googleapis.com/v1/projects/$PROJECT_ID/databases/(default)/documents/orders?key=$API_KEY"
        $resp = Invoke-RestMethod -Uri $url -TimeoutSec 10

        foreach ($doc in $resp.documents) {
            $docId = $doc.name.Split('/')[-1]
            $fields = $doc.fields
            $status = $fields.status.stringValue
            $isPrinted = $fields.printed.booleanValue

            if (-not $isPrinted -and -not $printedOrders.ContainsKey($docId) -and ($status -eq 'PAYED_CASH' -or $status -eq 'PAYED_CARD')) {
                $items = @()
                if ($fields.items.arrayValue.values) {
                    foreach ($v in $fields.items.arrayValue.values) {
                        $f = $v.mapValue.fields
                        $items += @{
                            name = $f.name.stringValue
                            price = if ($f.price.doubleValue) { $f.price.doubleValue } elseif ($f.price.integerValue) { $f.price.integerValue } elseif ($f.price.stringValue) { $f.price.stringValue } else { 0 }
                            details = $f.details.stringValue
                        }
                    }
                }

                $order = @{
                    orderNum = $fields.orderNum.stringValue
                    customerName = $fields.customerName.stringValue
                    customerPhone = $fields.customerPhone.stringValue
                    deliveryMode = $fields.deliveryMode.stringValue
                    address = $fields.address.stringValue
                    total = if ($fields.total.doubleValue) { $fields.total.doubleValue } elseif ($fields.total.integerValue) { $fields.total.integerValue } else { 0 }
                    status = $status
                    special = $fields.special.stringValue
                    createdAt = $fields.createdAt.timestampValue
                    items = $items
                }

                Write-Host "`n--- NOUVELLE COMMANDE ---" -ForegroundColor Yellow
                Write-Host "  #$($order.orderNum) - $($order.customerName) - $($order.total)EUR" -ForegroundColor Cyan
                Print-Ticket $order $docId
                Start-Sleep -Seconds 2
            }
        }
    } catch {
        Write-Host "Erreur connexion: $_" -ForegroundColor Red
    }
}

Clear-Host
Write-Host ""
Write-Host "========================================" -ForegroundColor Red
Write-Host "  AUTO-PRINTER - New Pizza Reims" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Red
Write-Host ""
Write-Host "Imprimantes detectees:" -ForegroundColor Cyan
Get-Printer | ForEach-Object { Write-Host "  - $($_.Name) (port: $($_.PortName))" -ForegroundColor Cyan }
Write-Host ""
Write-Host "En ecoute des nouvelles commandes..." -ForegroundColor Green
Write-Host "Appuyez sur Ctrl+C pour arreter" -ForegroundColor Gray
Write-Host ""

while ($true) {
    Check-Orders
    Start-Sleep -Seconds $POLL_INTERVAL
}
