class TextBoxModel {
  final int? id;
  final int pageId;
  final String text;
  final double x;
  final double y;
  final double width;
  final double height;
  final double fontSize;
  final int colorValue;

  TextBoxModel({
    this.id,
    required this.pageId,
    required this.text,
    required this.x,
    required this.y,
    this.width = 200,
    this.height = 80,
    this.fontSize = 16,
    this.colorValue = 0xFF000000, // Black color default
  });

  TextBoxModel copyWith({
    int? id,
    int? pageId,
    String? text,
    double? x,
    double? y,
    double? width,
    double? height,
    double? fontSize,
    int? colorValue,
  }) {
    return TextBoxModel(
      id: id ?? this.id,
      pageId: pageId ?? this.pageId,
      text: text ?? this.text,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      fontSize: fontSize ?? this.fontSize,
      colorValue: colorValue ?? this.colorValue,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'page_id': pageId,
      'text': text,
      'x': x,
      'y': y,
      'width': width,
      'height': height,
      'font_size': fontSize,
      'color': colorValue,
    };
  }

  factory TextBoxModel.fromMap(Map<String, dynamic> map) {
    return TextBoxModel(
      id: map['id'] as int?,
      pageId: map['page_id'] as int,
      text: map['text'] as String,
      x: map['x'] as double,
      y: map['y'] as double,
      width: map['width'] as double? ?? 200,
      height: map['height'] as double? ?? 80,
      fontSize: map['font_size'] as double? ?? 16,
      colorValue: map['color'] as int? ?? 0xFF000000,
    );
  }
}
