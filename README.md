# 目次
- [前提](#前提)
- [構成手順](#構成手順)
  - [設定カタログプロファイルの App Configuration への登録](#設定カタログプロファイルの-app-configuration-への登録)
    - [設定カタログプロファイルの作成](#設定カタログプロファイルの作成)
    - [Graph API アクセス用 Entra ID アプリの登録](#graph-api-アクセス用-entra-id-アプリの登録)
    - [設定カタログプロファイルのエクスポート](#設定カタログプロファイルのエクスポート)
    - [App Configuration への JSON オブジェクトの登録](#app-configuration-への-json-オブジェクトの登録)
  - [Logic Apps フローの編集](#logic-apps-フローの編集)
  - [Power Automate フローの編集](#power-automateフローの編集)
# 前提
本ガイドの手順を進める前に以下基礎ガイドを元にした構成が完了している必要があります。

[Microsoft サーバーレスフローからセキュアに App Configuration パラメータにアクセスする](https://github.com/TK3214-MS/POC-AppConf)

![00](https://github.com/TK3214-MS/POC-Utilize-AppConf/assets/89323076/9f013b20-b585-464a-baea-d68d2ea5fe6e)

本シナリオで想定しているフローは以下の通りです。

1. Power Apps アプリ上で２つの値(App Configuration構成ストアの”キー”と”ラベル”を指定し、ボタン押下アクションを実行し、Power Automate を開始する。
2. Power Automate から認証ポリシーで保護された Logic Apps フローを実行試行し、Power Automate HTTP アクションに設定した Entra ID アプリケーション情報が認証ポリシーと合致すれば、Logic Apps フローがパラメーター指定され開始する。
3. Logic Apps から Function App を実行試行し、Function に設定された認証設定／プロバイダー情報に Logic Apps に設定された Managed Identities 情報と合致すれば、Function App がパラメーター指定され開始する。
4. Function App が App Configuration に接続試行を行い、Function に設定された Managed Identities の RBAC 設定が App Configuration に設定されていれば、App Configuration からのバリュー取得試行を行う。
5. パラメーター指定されたキー／ラベルを元にバリューがFunction App に返され、同じく HTTP アクション実行後の Body を待機する Logic Appsに返ってきた JSON オブジェクトを元に Graph API に対して設定カタログの作成を行う。

# 構成手順
## 設定カタログプロファイルの App Configuration への登録
### 設定カタログプロファイルの作成
a. 以下手順を参照し、Microsoft Endpoint Manager コンソールで設定カタログプロファイルを作成します。

[Use the setting catalog to configure settings on Windows, iOS/iPadOS and macOS devices](https://learn.microsoft.com/en-us/mem/intune/configuration/settings-catalog)

### Graph API アクセス用 Entra ID アプリの登録
a. Azure ポータルで Azure Active Directory メニューを開き、”App registration”を選択し新規アプリを以下設定値で登録します。

| 設定名 | 設定値 |
| ------------- | ------------- |
| `Name` | 任意のアプリ識別名を入力 |
| `Supported account types` | Accounts in this organizational directory only |
| `Redirect URI` | 空白 |

b. 作成したアプリのApplication IDをメモします。

![01](https://github.com/TK3214-MS/POC-Utilize-AppConf/assets/89323076/2bf8a961-8f0c-4da2-8f79-9b854133bde1)

c. 作成したアプリにクライアントシークレットを作成し、生成された値をメモします。

![02](https://github.com/TK3214-MS/POC-Utilize-AppConf/assets/89323076/899ce039-914c-4780-b72b-cb3b48f58aa3)

d. メモした Application ID と Client Secret を Key Vault シークレットとして登録します。

![03](https://github.com/TK3214-MS/POC-Utilize-AppConf/assets/89323076/fffd1249-a035-4e30-ac19-116f66b0dda3)

e. Key Vault の RBAC に Logic Apps Managed Identities をKey Vault Administrator ロールとして登録します。

![04](https://github.com/TK3214-MS/POC-Utilize-AppConf/assets/89323076/a1adba46-b9b7-44bb-87a6-284f269b58bd)

### 設定カタログプロファイルのエクスポート
a. ローカル管理者 PowerShell で変数を定義します。
```powershell
# 設定カタログエクスポートファイルを保存するディレクトリを指定
Add-Type -AssemblyName System.Windows.Forms
$FolderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog -Property @{ 
  RootFolder = "MyComputer"
  Description = '設定カタログファイルをエクスポートするフォルダを選択して下さい。'
}
if($FolderBrowser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK){
  $location = $FolderBrowser.SelectedPath
}

$clientid = "メモした Graph アクセス用 Entra ID アプリの Application ID"
$tenantName = "<自身のドメイン>.onmicrosoft.com"
$clientSecret = "メモした Graph アクセス用 Entra ID アプリの シークレット値"
```

b. アクセストークンを取得します。
```powershell
$ReqTokenBody = @{
  Grant_Type    = "client_credentials"
  Scope         = "https://graph.microsoft.com/.default"
  client_Id     = $clientID
  Client_Secret = $clientSecret
  }

$TokenResponse = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$tenantName/oauth2/v2.0/token" -Method POST -Body $ReqTokenBody
```

c. Microsoft Endpoint Manager 設定カタログプロファイルを取得します。
```powershell
$authHeaders = @{Authorization = "Bearer $($Tokenresponse.access_token)"}
$restParam = @{
  Method      = 'Get'
  Uri         = 'https://graph.microsoft.com/beta/deviceManagement/configurationPolicies'
  Headers     = $authHeaders
  ContentType = 'Application/json'
  }
$configPolicies = Invoke-RestMethod @restParam
$configPolicies.value
```

d. Microsoft Endpoint Manager 設定カタログプロファイル詳細を取得します。
```powershell
$configPoliciesDetails = foreach ($Policy in $configPolicies.value) {
  $restParam = @{
    Method      = 'Get'
    Uri         = "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies('$($Policy.id)')/settings?`$expand=settingDefinitions&top=1000"
    Headers     = $authHeaders
    ContentType = 'Application/json'
    }
  Invoke-RestMethod @restParam
}

```

e. Microsoft Endpoint Manager 設定カタログプロファイルをエクスポートします。
```powershell
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
```

### App Configuration への JSON オブジェクトの登録
a. Azureポータルから以下設定値でLogic Appsリソースを作成します。

![05](https://github.com/TK3214-MS/POC-Utilize-AppConf/assets/89323076/a363c5c8-0140-481c-ab08-187d7118a44a)

サンプルで利用したJSONファイルは以下の通りです。

```json
{
    "name":  "POC Setting Catalog",
    "description":  "",
    "platforms":  "windows10",
    "technologies":  "mdm",
    "roleScopeTagIds":  [
        "0"
    ],
    "settings":  [
        {
            "settingInstance":  {
                "@odata.type":  "#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance",
                "settingDefinitionId":  "device_vendor_msft_bitlocker_requiredeviceencryption",
                "settingInstanceTemplateReference":  null,
                "choiceSettingValue":  {
                    "settingValueTemplateReference":  null,
                    "value":  "device_vendor_msft_bitlocker_requiredeviceencryption_1",
                    "children":  [
                    ]
                }
            }
        }
    ]
}
```

## Logic Apps フローの編集
既に作成済みの Logic Apps フローに追加編集を行います。
追加した各フロー内アクションの設定値は以下の通りです。

### When a HTTP request is received
![06](https://github.com/TK3214-MS/POC-Utilize-AppConf/assets/89323076/03f89259-c170-44d3-a8fb-9784571feb7a)

| 設定名 | 設定値 |
| ------------- | ------------- |
| `HTTP POST URL` | 自動生成 |
| `Request Body JSON Schema` | { <br>   "key":"", <br>    "label":"", <br>    "policyname":""} <br> ※Use sample payload to generate schemaから上記サンプルスキーマを入力し生成 |

### Initialize Policy Name

![07](https://github.com/TK3214-MS/POC-Utilize-AppConf/assets/89323076/3d5c24db-f318-4381-b45d-37c77ba883a5)

| 設定名 | 設定値 |
| ------------- | ------------- |
| `Name` | PolicyName |
| `Type` | String |
| `Value` | HTTPトリガーから`policyname`を参照 |

### Parse JSON

![08](https://github.com/TK3214-MS/POC-Utilize-AppConf/assets/89323076/7fa5d213-8f1d-40f5-bc32-7e50e3519777)

| 設定名 | 設定値 |
| ------------- | ------------- |
| `Content` | Function アクションの `Body` を参照 |
| `Schema` | Use sample payload to generate schemaから抽出済みJSONファイル内容を貼り付け生成 |

### Initialize JSON Body

![09](https://github.com/TK3214-MS/POC-Utilize-AppConf/assets/89323076/59b20f16-7979-40e8-b09b-9ef946e39954)

| 設定名 | 設定値 |
| ------------- | ------------- |
| `Name` | Body |
| `Type` | Object |
| `Value` | Parse JSON アクションより`Body`を参照 |

### Set Policy Name

![10](https://github.com/TK3214-MS/POC-Utilize-AppConf/assets/89323076/63cebe5c-1a06-4859-a527-6a7b8208b8e0)

| 設定名 | 設定値 |
| ------------- | ------------- |
| `Inputs` | setProperty(variables('Body'),'name',variables('PolicyName')) |

### Invoke Graph API

![11](https://github.com/TK3214-MS/POC-Utilize-AppConf/assets/89323076/cb161ae0-5b81-45ca-a1a3-037d869250f9)

| 設定名 | 設定値 |
| ------------- | ------------- |
| `Method` | POST |
| `URI` | https://graph.microsoft.com/beta/deviceManagement/configurationPolicies |
| `Headers` | Content-Type:application/json |
| `Body` | Set Policy Name アクションより Output を参照 |
| `Authentication type` | Active Directory Oauth |
| `Tenant` | 自身のテナントID |
| `Audience` | https://graph.microsoft.com |
| `Client ID` | Key Vault 参照から Client ID を参照 |
| `Credential Type` | Secret |
| `Secret` | Key Vault 参照から Client Secret を参照 |

## Power Automateフローの編集
既に作成済みの Power Automate フローに追加編集を行います。
追加した各フロー内アクションの設定値は以下の通りです。

各フロー内アクションの設定値は以下の通りです。

### PowerApps (V2)
![12](https://github.com/TK3214-MS/POC-Utilize-AppConf/assets/89323076/bfb56212-85ab-4014-bdd9-464a36fae6b2)

| 設定名 | 設定値 |
| ------------- | ------------- |
| `key` | key value |
| `label` | label value |
| `policyname` | policyname value |

### HTTP

![13](https://github.com/TK3214-MS/POC-Utilize-AppConf/assets/89323076/840dce3b-7e44-4c96-93b4-e37ab36cf498)

| 設定名 | 設定値 |
| ------------- | ------------- |
| `方法` | POST |
| `URI` | `Memo.LA.POSTURL` |
| `本文` | { <br>  "key": PowerAppsトリガーから`key`を参照, <br>  "label": PowerAppsトリガーから`label`を参照, <br> "policyname":PowerAppsトリガーから`policyname`を参照 <br> } |
| `認証` | Active Directory OAuth |
| `テナント` | `Memo.DirectoryID` |
| `対象ユーザー` | `Memo.LA.EntraApp.ID` |
| `クライアントID` | `Memo.PA.EntraApp.ID` |
| `資格情報の種類` | シークレット |
| `シークレット` | `Memo.PA.EntraApp.SC` |