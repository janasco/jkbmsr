/// Represents the authenticated user profile and JWT.
/// Maps exactly to the `/v1/user/login` and `/v1/user/register` response.
class User {
  final String id;
  final String email;
  final String token;

  User({
    required this.id,
    required this.email,
    required this.token,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    // If the token is returned directly inside the payload (e.g. root JSON object),
    // we can parse the nested 'user' node or the root elements.
    final userJson = json['user'] as Map<String, dynamic>? ?? {};
    return User(
      id: (userJson['id'] ?? json['id'] ?? '') as String,
      email: (userJson['email'] ?? json['email'] ?? '') as String,
      token: (json['token'] ?? '') as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'token': token,
      'user': {
        'id': id,
        'email': email,
      },
    };
  }
}
