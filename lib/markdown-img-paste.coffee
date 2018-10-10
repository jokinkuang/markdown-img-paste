{CompositeDisposable} = require 'atom'
{dirname, join} = require 'path'
clipboard = require 'clipboard'
fs = require 'fs'


module.exports =
    subscriptions : null

    activate : ->
        @subscriptions = new CompositeDisposable
        @subscriptions.add atom.commands.add 'atom-workspace',
            'markdown-img-paste:paste' : => @paste()

    deactivate : ->
        @subscriptions.dispose()

    paste : ->
        if !cursor = atom.workspace.getActiveTextEditor() then return

        #In case text gets posted into the file Atom should behave normal
        text = clipboard.readText()
        # if the user copied text we don't care about different formats.
        # just let him do it
        if(text)
            editor = atom.workspace.getActiveTextEditor()
            editor.insertText(text)
            return

        #只在markdown中使用
        if atom.config.get 'markdown-img-paste.only_markdown'
            if !grammar = cursor.getGrammar() then return

            if cursor.getPath()
                if  cursor.getPath().substr(-3) != '.md' and
                    cursor.getPath().substr(-9) != '.markdown' and
                    grammar.scopeName != 'source.gfm'
                        return
            else
                if grammar.scopeName != 'source.gfm' then return

        img = clipboard.readImage()
        if img.isEmpty() then return

        editor = atom.workspace.getActiveTextEditor()
        # Words equals the text in the current line of the cursor
        words = editor.lineTextForBufferRow(editor.getCursorBufferPosition().row)
        words = words.replace(/\s|\\|\//g, "-");
        # alert words

        # We delete anything in the current line
        editor.deleteLine()
        # Restore the cursor.column to first column
        position = editor.getCursorBufferPosition()
        position.column = 0
        editor.setCursorBufferPosition position

        #Sets filename based on datetime
        filename = words+".png"
        #We dont want spaces in our filename. Special charackters are not considered yet
        filename = filename.replace(/\s/g, "");

        #Sets up image assets folder
        curDirectory = dirname(cursor.getPath()) + "/"
        fullname = join(curDirectory, filename)

        subFolderToUse = ""
        if atom.config.get 'markdown-img-paste.use_subfolder'
            #Finds  directory path
            subFolderToUse = atom.config.get 'markdown-img-paste.subfolder'

            if subFolderToUse != ""
              assetsDirectory = join(curDirectory, subFolderToUse) + "/"

              #Creates directory if necessary
              if !fs.existsSync assetsDirectory
                fs.mkdirSync assetsDirectory

              #Sets full img path
              fullname = join(assetsDirectory, filename)

        fs.writeFileSync fullname, img.toPNG()

        #上传至sm.ms
        if atom.config.get 'markdown-img-paste.upload_to_mssm'
            request = require 'request'

            options =
                uri: 'https://sm.ms/api/upload'
                headers:
                    'user-agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/53.0.2785.143 Safari/537.36'
                formData:
                    smfile: fs.createReadStream fullname

            request.post options, (err, response, body) ->
                if err
                    atom.notifications.addError 'Upload failed:' + err
                else
                    console.log(body)
                    body = JSON.parse body
                    if body.code == 'error'
                        atom.notifications.addError 'Upload failed:' + body.msg
                    else
                        atom.notifications.addSuccess 'OK, image upload to sm.ms!'
                        mdtext = '!['+words+'](' + body.data.url + ')'
                        paste_mdtext cursor, mdtext

            delete_file(fullname)

            #完成
            return


        #保存在本地
        if !atom.config.get('markdown-img-paste.upload_to_qiniu')
            mdtext = '!['+words+']('
            subFolderToUse = ""
            if atom.config.get 'markdown-img-paste.use_subfolder'
                subFolderToUse = atom.config.get 'markdown-img-paste.subfolder'
                mdtext += subFolderToUse + "/"

            mdtext += filename + ')'
            mdtext += '\r\n'

            paste_mdtext cursor, mdtext

        #使用七牛存储图片
        else
            qiniu = require 'qiniu'

            qiniu.conf.ACCESS_KEY = atom.config.get 'markdown-img-paste.zAccessKey'
            qiniu.conf.SECRET_KEY = atom.config.get 'markdown-img-paste.zSecretKey'

            #要上传的空间
            bucket = atom.config.get 'markdown-img-paste.zbucket'

            #七牛空间域名
            domain = atom.config.get 'markdown-img-paste.zdomain'

            #上传到七牛后保存的文件名
            key = filename

            #构建上传策略函数
            uptoken = (bucket, key) ->
                putPolicy = new qiniu.rs.PutPolicy(bucket+":"+key)
                putPolicy.token()

            #生成上传 Token
            token = uptoken bucket, key

            #要上传文件的本地路径
            filePath = fullname

            #设置上传服务器域名
            uphost = atom.config.get 'markdown-img-paste.zuphost'
            if uphost
                qiniu.conf.UP_HOST = uphost

            #构造上传函数
            uploadFile = (uptoken, key, localFile) ->
                extra = new qiniu.io.PutExtra()
                qiniu.io.putFile uptoken, key, localFile, extra, (err, ret) ->
                    if !err
                        #上传成功， 处理返回值
                        #console.log(ret.hash, ret.key, ret.persistentId);
                        atom.notifications.addSuccess 'OK, image upload to qiniu!'

                        pastepath =  domain + '/' +  filename
                        mdtext = '!['+words+'](' + pastepath + ')'
                        paste_mdtext cursor, mdtext
                    else
                        #上传失败， 处理返回代码
                        atom.notifications.addError 'Upload Failed:' + err.error
                        console.log(err);

            #调用uploadFile上传
            uploadFile token, key, filePath

            delete_file fullname

#辅助函数
delete_file = (file_path) ->
    fs.unlink file_path, (err) ->
        if err
            console.log '未删除本地文件:'+ fullname

paste_mdtext = (cursor, text) ->
    cursor.insertText text
    position = cursor.getCursorBufferPosition()
    position.row = position.row - 1
    position.column = position.column + text.length + 1
    cursor.setCursorBufferPosition position


Date.prototype.format = ->

    shift2digits = (val) ->
        if val < 10
            return "0#{val}"
        return val

    year = @getFullYear()
    month = shift2digits @getMonth()+1
    day = shift2digits @getDate()
    hour = shift2digits @getHours()
    minute = shift2digits @getMinutes()
    second = shift2digits @getSeconds()
    ms = shift2digits @getMilliseconds()

    return "#{year}#{month}#{day}#{hour}#{minute}#{second}#{ms}"
