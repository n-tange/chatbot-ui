# CHATBOT-UI を CloudRun で動かしてみよう

## ドキュメント内のパラメータ

| パラメータ名                        | 値                                    |
| ----------------------------------- | ------------------------------------- |
| OpenAI アカウントの ORGANIZAION_ID  | <OpenAI アカウントの ORGANIZAION_ID>  |
| OpenAI アカウントで作成した API_KEY | <OpenAI アカウントで作成した API_KEY> |
| GCP の プロジェクト名               | <GCP の プロジェクト名>               |

## fork 元からの修正

[CHATBOT-UI の fork 元](https://github.com/mckaywrigley/chatbot-ui)からの修正点は以下

- Dockerfile

  - FROM に --platform=linux/amd64 オプションを追加（Cloud Run で動かすため）

    ```DockerFile
    FROM --platform=linux/amd64 node:19-alpine AS base
    ...
    ```

  - EXPOSE に 8080 を追加（Cloud Run のデフォルトポート 8080 で動かすため）

    ```DockerFile
    EXPOSE 3000 8080
    ```

- docker-compose.yaml
  以下のように修正。（起動するときは chatgpt-ui というタグでビルドした後、OpenAI のアカウント関連情報を書き換えて docker compose up をする。）

  ```yaml
  version: '3.6'

  services:
    chatgpt:
      image: chatgpt-ui:latest
      ports:
        - 3000:3000
        - 8080:8080
      environment:
        - 'PORT=8080'
        - 'OPENAI_ORGANIZATION=<OpenAI アカウントの ORGANIZAION_ID>'
        - 'OPENAI_API_KEY=<OpenAI アカウントで作成した API_KEY>'
  ```

- next-i18next.config.js
  デフォルトのロケールを ja に修正

  ```javascript
    defaultLocale: 'ja',
  ```

- cloudrun/env.yaml

  ディレクトリとファイルを作成。CloudRun にデプロイする際の環境変数を定義。

  ```yaml
  OPENAI_ORGANIZATION: <OpenAI アカウントの ORGANIZAION_ID>
  OPENAI_API_KEY: <OpenAI アカウントで作成した API_KEY>
  ```

## docker image のビルド

ソースを docker image をビルド、タグ付けし、Google の Artifact Registory に登録する

```sh
# imageのビルド
docker build -t chatgpt-ui .

# イメージのタグ付け
docker tag chatgpt-ui gcr.io/<GCP の プロジェクト名>/chatgpt-ui:latest

# Artifact Registoryへの登録
docker push gcr.io/<GCP の プロジェクト名>/chatgpt-ui:latest
```

## CloudRun へのデプロイ

CloudRun にサービスをデプロイ。使用ポートがデフォルトの 8080 になるようにビルド済み。

```bash
gcloud beta run deploy chatgpt-ui --image gcr.io/<GCP の プロジェクト名>/chatgpt-ui:latest \
--region us-central1 \
--allow-unauthenticated \
--env-vars-file ./cloudrun/env.yaml \
--memory 512Mi \
--cpu 1 \
--timeout 300 \
--concurrency 20 \
--min-instances 0 \
--max-instances 3 \
```

## お名前.com でドメインの取得

IAP でアクセス制御するためにロードバランサーを CloudRun サービスの前段に設置する。そのためのドメインを取得する。  
とりあえずお名前.com で取得したドメインを使用してみた。

## 静的外部 IP アドレスを予約する

- ポイント

  - ここで予約する静的外部 IP アドレスは CloudDNS の設定とロードバランサーの設定に使用する
  - 静的外部 IP アドレスはロードバランサーに設定しないと料金がかかるため、注意すること

- 手順

  1. GoogleCloudConsole で「VPC ネットワーク」＞「IP アドレス」を選択
  2. 「外部静的アドレスを予約」をクリック
  3. 「名前」はわかりやすい任意の名前を入力
  4. 「ネットワークサービスティア」は「プレミアム」を選択
  5. 「IP バージョン」は「IPv4」を選択
  6. 「タイプ」は「グローバル」を選択
  7. 「予約」ボタンをクリックして IP アドレスを予約する
  8. 予約された静的外部 IP アドレスを覚えておく

## CloudDNS で独自ドメインを設定する

- ポイント

  - お名前.com で作成したドメインを使用して、CloudDNS を設定する

- 手順

  1. GoogleCloudConsole で 「ネットワークサービス」 ＞「Cloud DNS」を選択
  2. 「ゾーン」を作成をクリックする
  3. 「ゾーンのタイプ」は「公開」を選択
  4. 「ゾーン名」は任意のわかりやすい名前を指定
  5. 「DNS 名」はお名前.com で取得したドメインを指定
  6. 「DNSSEC」はオン（オンにしないと SSL 証明書の PROVISIONING が通らないかも）
  7. 「作成」ボタンを押してゾーンを作成
  8. ゾーンの一覧画面で作成したゾーンを選択し、「ゾーンの詳細」画面に移動
  9. 「レコードセットを追加」をクリック
  10. サブドメインを指定する場合、「DNS 名」にサブドメイン名を入力
  11. 「IPv4 アドレス」に予約した静的外部 IP アドレスを入力
  12. 「作成」ボタンをクリックしレコードセットを作成
  13. 「ゾーンの詳細」画面でレコードセットの一覧から種類が「NS」のレコードを探して、行を展開し NS レコードをすべてメモしておく（操作段階では、ns-cloud-c1.googledomains.com.〜ns-cloud-c4.googledomains.com.のレコード 4 件があった）

## お名前.com にネームサーバー設定を反映する

- ポイント

  - Cloud DNS で設定した DNS サーバーをお名前.com(レジストラ)のネームサーバーに指定することで作成したドメインが Cloud DNS の DNS サーバーで管理されていることを他の DNS サーバーに伝播することができる

- 手順

  1. お名前.com Navi にログインする
  2. 「ネームサーバーの設定」＞「ネームサーバーの設定」を選択する
  3. 取得したドメイン名を選択して「他のネームサーバーを利用」タブをクリック
  4. 「ネームサーバー情報を入力」の欄に、Cloud DNS でメモした NS レコードをすべて入力する（末尾に . がある場合、入力チェックに引っかかるので除外した）
  5. 確認画面で、「設定する」ボタンをクリックする
  6. 反映に少し時間がかかるため注意

### Cloud LoadBalancing でロードバランサーを設定する

- ポイント

  - ロードバランサを設定するにはフロントエンド、バックエンド、ルーティングルールの構成を順に行う
  - フロントエンドの構成時に予約した静的外部 IP アドレスを指定する
  - フロントエンドの構成時に取得したドメインを指定したマネージド SSL 証明書を作成する
  - バックエンドの構成時に作成した CloudRun サービスを指定する

- 手順

  1. GoogleCloudConsole で 「ネットワークサービス」 ＞「ロードバランシング」を選択
  2. 「ロードバランサを作成」をクリック
  3. 「HTTP(S)ロード バランシング」の「構成を開始」をクリック
  4. 「インターネット接続または内部専用」は「インターネットから VM またはサーバーレス サービスへ」を選択
  5. 「グローバル / リージョン」は「グローバル HTTP(S) ロードバランサ」を選択
  6. 「新しいロードバランサ」画面で、「名前」欄にロードバランサの名前を入力（任意のわかりやすい名前）
  7. 「フロントエンドの構成」をクリック
  8. 「新しいフロントエンドの IP とポート」の入力欄を埋めていく
     1. 「名前」欄にフロントエンドの名前を入力（任意のわかりやすい名前）
     2. 「プロトコル」は「HTTPS(HTTP/2 を含む)」を選択
     3. 「ip address」は予約した静的外部 IP アドレスを選択
     4. 「証明書」欄をクリックし、「新しい証明書を作成」をクリックする
     5. 「証明書の作成」画面で「名前」欄に証明書の名前を入力（任意のわかりやすい名前）
     6. 「証明書の作成」画面の「作成モード」は「Google マネージドの証明書を作成する」を選択
     7. 「証明書の作成」画面の「ドメイン」には取得したドメインのサブドメインを入力
     8. 「作成」をクリックして証明書を作成する
     9. 「HTTPS へのリダイレクトを有効にする」をチェックする
     10. 「完了」をクリックしてフロントエンドの構成を完了する
  9. 「バックエンドの構成」をクリック
  10. 「バックエンドサービスとバックエンドバケット」欄をクリック
  11. 「バックエンドサービスを作成」をクリックし
  12. 「バックエンドサービスを作成」の入力欄を埋めていく
      1. 「名前」欄にバックエンドの名前を入力（任意のわかりやすい名前）
      2. 「バックエンドタイプ」は「サーバーレス ネットワーク エンドポイント グループ」を選択
      3. 「新しいバックエンド」の「サーバーレス ネットワーク エンドポイント グループを作成」を選択
      4. 「サーバーレス ネットワーク エンドポイント グループを作成」の「名前」に任意の名前を入力
      5. 「サーバーレス ネットワーク エンドポイント グループを作成」の「リージョン」は作成した CloudRun サービスと同じリージョンを選択
      6. 「サーバーレス ネットワーク エンドポイント グループを作成」の「Cloud Run」を選択
      7. 表示された「サービスを選択」で作成した Cloud Run サービスを選択
      8. 「サーバーレス ネットワーク エンドポイント グループを作成」の「作成」ボタンをクリックして戻る
      9. 「Cloud CDN を有効にする」のチェックは外す
      10. 「作成」ボタンをクリック
  13. 「ルーティングルール」は初期状態のまま、下部の「作成」ボタンをクリック

## SSL 証明書が作成できているか確認する

- ポイント

  - SSL 証明書のステータスが ACTIVE になると SSL 通信が可能になるが、時間がかかる場合がある
  - SSL 証明書のステータスを ACTIVE にするには、ドメインの DNS をロードバランサーに向ける必要がある（お名前.com にネームサーバー設定を反映する　の手順が必要）

- 手順
  1. GoogleCloudConsole で 「ネットワークサービス」 ＞「ロードバランシング」を選択
  2. 作成したロードバランサーの名前をクリック
  3. 「フロントエンド」の「証明書」列にある作成した SSL 証明書の名前をクリック
  4. 「ステータス」を確認
  5. 「ステータス」が PROVISIONING となっているときは証明書の準備中なのでもうしばらく待つ
  6. 「ステータス」が FAILED_NOT_VISIBLE となっている時は、お名前.com のネームサーバー設定を見直す（お名前.com の設定が有効になったら自然にステータスが変更される
  7. 「ステータス」が ACTIVE になったら、SSL 証明書が有効になり、CloudRun サービス と https 通信が可能になる
  8. `https://CloudDNSで作成したサブドメイン` でアクセスし CloudRun サービス の応答があるか確認する

## CloudRun サービスの URL のアクセスを封じる

CloudRun のサービスをロードバランサーからのアクセスさせるため、CloudRun サービスの URL からのアクセスをできなくする

- 手順

  1. GoogleCloudConsole で 「Cloud Run」 ＞作成した CloudRun サービスを選択
  2. 「ネットワーキング」タブを選択
  3. 「Ingress の制御」で「内部」を選択し、「外部 HTTP(S) ロードバランサからのトラフィックを許可する」にチェックを入れる
  4. 「保存」をクリックする。（リビジョンの更新が実施される）

## OAuth 画面の準備

ロードバランサーにアクセスした時に認証用の画面としての OAuth 画面を準備する

- 手順
  1. GoogleCloudConsole で 「API とサービス」 ＞「OAuth 同意画面」を選択
  2. 「公開ステータス」を「本番」に設定
  3. 「ユーザーの種類」を「外部」に設定

## 認証用のグループを作成する

IAP を経由で CloudRun サービスへのアクセス許可を与えるための Google グループを作成する。
このグループに所属するユーザーが CloudRun サービスにアクセスできるようになる.
（グループの所属元組織の管理者で操作すること）

- 手順

  1. GoogleCloudConsole でプロジェクトを組織に変更する
  2. 「IAM と管理」>「グループ」を選択する
  3. グループ名、グループのメールアドレス、グループの説明を任意のわかりやすい内容で入力し「保存」ボタンを押す
  4. グループの詳細 で「Google グループでこのグループを管理」をクリックする
  5. Google グループの画面で左のメニュー > グループ設定をクリックする
  6. 「グループを表示できるユーザー」が「組織のメンバー」にする（または、なっていることを確認する）
  7. 「会話を閲覧できるユーザー」を「グループのオーナー」にする
  8. 「投稿できるユーザー」を「グループのオーナー」にする
  9. 「メンバー一覧を表示できるユーザー」を「グループのマネージャー」にする
  10. 「投稿ポリシー」 > 「メールでの投稿を許可」、「ウェブからの投稿を許可」のチェックを外す
  11. [admin.google.com](https://admin.google.com) にグループが所属する組織にログインする
  12. admin.google.com のホームからグループをクリックする
  13. グループの一覧で作成したグループを選択する
  14. 「アクセス設定」を選択し、「組織外メンバーの許可」のトグルを ON にして、「保存」をクリックする

## ロードバランサーに対して IAP を有効にする

作成したロードバランサで IAP を使用するようして、CloudRun サービスにログインする際に、Google アカウントの認証が要求されるようにする

- 手順
  1. GoogleCloudConsole で 「IAM と管理」 ＞「Identity-Aware Proxy」を選択
  2. 「アプリケーション」タブで、ロードバランサー作成時に同時に作成したバックエンドサービスの行の「IAP」トグルを ON にする
  3. 同行の左端のチェックボックスを ON にする
  4. 右側に表示された「プリンシパルを追加」をクリックする
  5. 「新しいプリンシパル」に作成した認証用グループを入力する
  6. 「ロールを選択」で「IAP-secured Web App User」を選択する
  7. 「保存」をクリックする

## 認証用のグループにユーザーを追加する

認証用のグループに利用者の Google アカウントを追加する。利用者は、Google アカウントでログインすることにより、CloudRun サービスにアクセスできるようになる。

- 手順
  1. [Google Group](https://groups.google.com/)にグループのオーナーでログインする
  2. 左のメニュー > マイグループで一覧から作成したグループを選択する
  3. 左のメニュー > ユーザー > メンバー を選択する
  4. 「メンバーを追加」をクリックする
  5. 「グループ メンバー」の欄に、利用者の Gmail アドレスを入力する
  6. 「メンバーを直接追加」のトグルを ON にして、「メンバーを追加」をクリックする
