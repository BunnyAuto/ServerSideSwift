//
//  NoteController.swift
//  App
//
//  Created by 晋先森 on 2018/9/6.
//

import Foundation
import Vapor
import Fluent
import FluentPostgreSQL
import Authentication

struct NoteController: RouteCollection {
    
    func boot(router: Router) throws {
        
        router.group("note") { (router) in
            
            // 提交 Live
            router.post(LiveContainer.self, at: "live", use: postLiveDataHandler)
            
            // 获取所有 Lives ,可选参数 page
            router.get("lives", use: getLivesDataHandler)
        }
    }
}


extension NoteController {
    
    func getLivesDataHandler(_ req: Request) throws -> Future<Response> {
        
        let token = BearerAuthorization(token: req.token)
        return AccessToken.authenticate(using: token, on: req).flatMap({ _ in
            
            let futureAllLives = NoteLive.query(on: req).query(page: req.page).all()
            
            return futureAllLives.flatMap({
                
                // 取出查询到的动态数组中的所有 userID
                let allIDs = $0.compactMap({ return $0.userID })
                
                // 取出此用户数组中的 用户信息，可能会出现 5条动态，只有3条用户信息，因为5条信息总共是3个人发的
                let futureAllInfos = UserInfo.query(on: req).filter(\.userID ~~ allIDs).all()
                
                struct ResultLive: Content {
                    
                    var userInfo: UserInfo?
                    
                    var title: String
                    var time: TimeInterval?
                    var content: String?
                    var imgName: String?
                    var desc: String?
                }

                return flatMap(to: Response.self, futureAllLives, futureAllInfos, { (lives, infos) in
                    
                    var results = [ResultLive]()
                    
                    //拼接返回数据，双层 forEach 效率怕是有影响，期待有更好的方法。🙄
                    lives.forEach({ (live) in
                        
                        var result = ResultLive(userInfo: nil,
                                                title: live.title,
                                                time: live.time,
                                                content: live.content,
                                                imgName: live.imgName,
                                                desc: live.desc)
                        
                        infos.forEach({
                            if $0.userID == live.userID {
                                result.userInfo = $0
                            }
                        })
                        
                        results.append(result)
                    })
                    return try ResponseJSON<[ResultLive]>(data: results).encode(for: req)
                })
            })
        })
    }
    
    
    private func postLiveDataHandler(_ req: Request, container: LiveContainer) throws -> Future<Response> {
        
        let token = BearerAuthorization(token: container.token)
        return AccessToken.authenticate(using: token, on: req).flatMap({
            guard let aToken = $0 else {
                return try ResponseJSON<Empty>(status: .token).encode(for: req)
            }
            
            var imgName: String?
            if let data = container.img?.data { //如果上传了图就判断、保存
                imgName = try VaporUtils.imageName()
                let path = try VaporUtils.localRootDir(at: ImagePath.note,
                                                       req: req) + "/" + imgName!
                guard data.count < ImageMaxByteSize else {
                    return try ResponseJSON<Empty>(status: .error,
                                                   message: "有点大，得压缩！").encode(for: req)
                }
                try Data(data).write(to: URL(fileURLWithPath: path))
            }
            
            let live = NoteLive(id: nil,
                                userID: aToken.userID,
                                title: container.title,
                                time: Date().timeIntervalSince1970,
                                content: container.content,
                                imgName: imgName,
                                desc: container.desc)
            
            return live.save(on: req).flatMap({ _ in
                return try ResponseJSON<Empty>.init(status: .ok,
                                                    message: "发布成功").encode(for: req)
            })
        })
    }
    
    
}


fileprivate struct LiveContainer: Content {
    
    var token: String
    var title: String
    var content: String?
    var img: File?
    var desc: String?
    
}







