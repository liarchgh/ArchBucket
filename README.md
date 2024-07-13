# Scoop Arch Bucket

`scoop bucket add Arch https://github.com/liarchgh/ArchBucket`

Personal scoop bucket

# Update

## 更新全部

```null script
cd bucket\ ; ls | get name | each { $in | path parse | get stem | powershell ..\bin\checkAndPush.ps1 $in }
```

## 更新指定app

```powershell
cd bucket
..\bin\checkAndPush.ps1 app_name
```
# Refs

[App-Manifests|Scoop](https://scoop-docs.vercel.app/docs/concepts/App-Manifests.html#a-simple-example)

