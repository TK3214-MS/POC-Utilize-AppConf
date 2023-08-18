# 設定カタログエクスポートファイルを保存するディレクトリを指定
Add-Type -AssemblyName System.Windows.Forms
$FolderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog -Property @{ 
    RootFolder = "MyComputer"
    Description = '設定カタログファイルをエクスポートするフォルダを選択して下さい、'
}

if($FolderBrowser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK){
    $location = $FolderBrowser.SelectedPath
}

# Entra ID 認証用アプリ登録情報を指定
$clientid = "dd14612c-caa5-4b5a-98f0-4dfc7b172b8a"
$tenantName = "MngEnvMCAP252835.onmicrosoft.com"
$clientSecret = "aOc8Q~3qJg1ChL~vZktHUuTKxZNqnPDceD1BbaLT"

# アクセストークンを取得
$ReqTokenBody = @{
    Grant_Type    = "client_credentials"
    Scope         = "https://graph.microsoft.com/.default"
    client_Id     = $clientID
    Client_Secret = $clientSecret
}
 
$TokenResponse = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$tenantName/oauth2/v2.0/token" -Method POST -Body $ReqTokenBody

# Intune 設定カタログアイテムを取得
$authHeaders = @{Authorization = "Bearer $($Tokenresponse.access_token)"}

$restParam = @{
    Method      = 'Get'
    Uri         = 'https://graph.microsoft.com/beta/deviceManagement/configurationPolicies'
    Headers     = $authHeaders
    ContentType = 'Application/json'
}

$configPolicies = Invoke-RestMethod @restParam
$configPolicies.value

# Intune 設定カタログアイテム詳細を取得
$configPoliciesDetails = foreach ($Policy in $configPolicies.value) {
    $restParam = @{
        Method      = 'Get'
        Uri         = "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies('$($Policy.id)')/settings?`$expand=settingDefinitions&top=1000"
        Headers     = $authHeaders
        ContentType = 'Application/json'
    }
    Invoke-RestMethod @restParam
}

# Intune 設定カタログアイテム詳細をエクスポート
$configPoliciesFormatted = foreach ($Policy in $configPolicies.value) {
    $restParam = @{
        Method      = 'Get'
        Uri         = "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies('$($Policy.id)')/settings?`$expand=settingDefinitions&top=1000"
        Headers     = $authHeaders
        ContentType = 'Application/json'
    }
    $PolicyDetails = Invoke-RestMethod @restParam

    [PSCustomObject]@{
        name            = $configPolicies.value.name
        description     = $configPolicies.value.description
        platforms       = $configPolicies.value.platforms
        technologies    = $configPolicies.value.technologies
        roleScopeTagIds = @($configPolicies.value.roleScopeTagIds)
        settings        = @(@{'settingInstance' = $configPoliciesDetails.value.settinginstance })
    }
}

$PolicyJSON = $configPoliciesFormatted | ConvertTo-Json -Depth 99
$raw = $PolicyJSON | Out-String | ConvertFrom-Json
$filePath = "$($location)\SettingCatalog - $($raw.name).json"
$PolicyJSON | Out-file $filePath