/// 环境开关：用 `--dart-define=ENV=prod` 构建时切到真实后端。
/// dev（默认）= MockRepository + 本地 assets；prod = RemoteRepository（待后端就绪后实现）。
class Env {
  static const String env = String.fromEnvironment('ENV', defaultValue: 'dev');
  static const bool isProd = env == 'prod';
}
