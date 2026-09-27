import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?
    private var tabs: BrowserTabCoordinator?

    func sceneDidEnterBackground(_ scene: UIScene) { tabs?.saveSession() }

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }

        let window = UIWindow(windowScene: windowScene)
        let coordinator = BrowserTabCoordinator()
        tabs = coordinator
        let navController = coordinator.navigationController
        
        window.rootViewController = navController
        self.window = window
        window.makeKeyAndVisible()
    }
}
