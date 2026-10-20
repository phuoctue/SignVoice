# Camera và service AI SignVoice

> Cách cài/chạy hiện hành trên máy khác: [SETUP_AI.md](SETUP_AI.md). Bản phát hành hiện dùng 181 từ và không dùng LM Studio trong nhận diện camera. Nội dung bên dưới là nhật ký triển khai cũ (gồm giai đoạn 144/234 từ và LM Vision), không dùng làm hướng dẫn chọn model hiện tại.

Flutter gửi ảnh trực tiếp đến Python/FastAPI cổng **8001**. Node cổng **3000** quản lý tài khoản, từ điển và lịch sử. Model, OpenCV và kết nối LM Studio chạy trong service Python riêng.

## Chạy trên máy này

1. Bật backend và database như trước: trong `backend`, chạy `npm run dev`.
2. Trong LM Studio, nạp **Qwen2.5 VL 7B Instruct**, bật Local Server cổng **1234**. Model Coder/embedding không thay được model Vision.
3. Chạy `Chay_AI_Service.bat`. Model mặc định ở thư mục cha `E:\WorkSpace\SignVoice`. Nếu service còn chạy mã cũ, dừng cửa sổ service và mở lại.
4. Chạy `Chay_App_AI_Web.bat`, hoặc:

   ```powershell
   flutter run -d chrome --web-port 8080 --dart-define=API_BASE_URL=http://localhost:3000/api/v1 --dart-define=AI_SERVICE_URL=http://localhost:8001
   ```

5. Mở **Ký hiệu → Giọng nói**. Màn hình giải thích quyền hiện trước; chỉ bấm **Cho phép camera** mới mở thiết bị và kết nối AI. Có thể chọn **Để sau** để quay lại. Nút đổi camera nằm trên khung ảnh. Màn hình chỉ có một kết quả, **Thêm vào câu**, nút đọc tiếng Việt và **Thử lại**.
6. Cài đặt góc phải chứa địa chỉ AI, chế độ Từ/Chữ/Số, đối chiếu ảnh LM Studio, lớp vẽ OpenCV và tự đọc. Đổi chế độ/camera tạo phiên mới để không trộn buffer cũ.

Flutter đang mở bản trước cần dừng và chạy lại. Không cần train Colab lại cho thay đổi giao diện, truyền ảnh và đối chiếu này.

## Quyền camera và microphone (sửa ngày 18/10)

- Camera và microphone có **màn hình giải thích xin quyền riêng**, với **Cho phép** và **Để sau**. Mỗi lần vào tính năng đều đi qua màn hình này, kể cả quyền trình duyệt đã được cấp trước đó. Nút thao tác luôn nằm ở chân trang; nội dung giải thích có thể cuộn trên màn hình nhỏ. App không gọi thiết bị khi vừa mở màn hình hoặc chọn Để sau.
- App gọi thiết bị và xin quyền trước khi kết nối AI. AI chưa chạy thì preview vẫn giữ và báo riêng **Chưa kết nối AI**. Không gộp lỗi quyền với lỗi nhận diện ký hiệu. Khi rời app rồi quay lại, camera không tự bật lại: cần bấm đồng ý trên màn xin quyền.
- **8080 là giao diện Flutter; 8001 là service AI riêng.** App chặn địa chỉ AI trỏ về gốc giao diện và giải thích cách sửa. `--dart-define=AI_SERVICE_URL=...` được ưu tiên hơn địa chỉ cũ lưu trong trình duyệt lúc khởi động; vẫn có thể chỉnh địa chỉ cho phiên hiện tại trong cài đặt.
- Trình duyệt hiển thị thông báo quyền thật khi cần. Nếu quyền đã được cho phép, sẽ không hỏi lại. Nếu đã bị chặn, mở biểu tượng bên trái thanh địa chỉ → Cài đặt trang web → Camera/Microphone → Cho phép, rồi tải lại. Dùng localhost hoặc HTTPS; app không tự đổi quyền trong trình duyệt.
- **Giọng nói → Văn bản** đã dùng `speech_to_text` để xin quyền và nhận giọng nói tiếng Việt của trình duyệt/thiết bị. Nút cũ chỉ đổi biến quyền và chèn câu demo đã được thay. Chỉ đánh dấu quyền sau khi engine thực sự bắt đầu nghe; không tự thu lúc mở trang.
- Đọc kết quả tiếng Việt dùng loa/TTS, không xin microphone. Nhận dạng lời nói có thể cần Internet/dịch vụ của thiết bị. Chưa kiểm thử microphone hoặc camera vật lý trong lần sửa này.
- Sau khi thêm plugin microphone, cần dừng phiên Flutter và chạy lại hoàn toàn; hot reload không đủ để đăng ký plugin mới.

Kiểm chứng lần sửa màn xin quyền: **100 kiểm thử Flutter qua**, gồm không bỏ qua màn đồng ý bằng cờ quyền cũ, Để sau không mở thiết bị, chặn URL nhầm cổng Flutter, xin camera trước AI, giữ preview khi AI offline, không gọi AI khi camera bị từ chối, chờ engine thật bắt đầu nghe trước khi đánh dấu quyền microphone, và không chèn câu demo. Kết nối thật từ origin `http://localhost:8080` đến `http://localhost:8001` đã qua health/CORS, WebSocket ready, ACK và kết quả của một khung đen. Không bật camera/microphone vật lý trong kiểm tra này.

Theo yêu cầu hiện tại, **không nạp model 234 từ** và **không khởi động lại service**. Service đang chạy vẫn báo **144 từ**; các file export mới trong thư mục cha được giữ nguyên.

Tham khảo: [quyền getUserMedia và HTTPS](https://developer.mozilla.org/en-US/docs/Web/API/MediaDevices/getUserMedia), [speech_to_text](https://pub.dev/packages/speech_to_text).

## LM Studio tham gia nhận diện

### Chữ số/chữ cái không chờ đối chiếu ảnh (18/10)

Chế độ **Chữ số** và **Chữ cái** gửi `vision=false` và trả kết quả từ classifier đang chạy. Công tắc đối chiếu bị vô hiệu hóa ở hai chế độ này, có lời giải thích trong cài đặt. Chế độ từ/cụm từ và Tất cả vẫn giữ tùy chọn đối chiếu. App lưu chế độ đã chọn, không tự quay lại `words` khi mở lại màn hình.

Video `Recording 2026-10-18 170041.mp4` cho thấy landmark và trạng thái chờ đối chiếu rồi lỗi đối chiếu. Lúc kiểm tra, AI 8001 hoạt động nhưng LM 1234 không phản hồi. Luồng cũ bật vision cả cho digits nên kết quả Colab có thể bị giữ lại ở bước sau. Bản sửa không đổi model/ngưỡng hoặc khởi động lại service.

Kiểm chứng: **104 kiểm thử Flutter qua**, gồm hello digits/letters gửi đúng `vision=false`, words giữ đối chiếu khi bật, và kết quả phản hồi được hiển thị. Replay ảnh từ quay màn hình chỉ phục vụ chẩn đoán, có overlay và không thay thế đánh giá accuracy trên video camera gốc. Để áp dụng: chạy lại Flutter, chọn **Chữ số**, lưu rồi thử 1–5. Không cần train Colab cho thay đổi này.

Khi model Colab xác nhận ký hiệu theo ngưỡng của bộ model, worker riêng gửi bảng ảnh gồm chuỗi camera và các mẫu tham chiếu đến Qwen VL bằng `image_url`. Mẫu phải có ID trong danh sách **TRAIN ghi trong cấu hình model**, đúng nhãn, không thuộc TEST/VAL; loại video đuôi B của từ điển gốc và skeleton mã số. Video kiểm thử người dùng không được dùng làm mẫu.

Qwen chọn mẫu phù hợp hoặc trả về chưa chắc chắn. Chỉ khi Qwen và Colab đồng ý trên cùng nhãn của chế độ hiện tại, service mới phát sự kiện xác nhận. Không đổi thành từ khác mà Colab chưa xác nhận. Các ứng viên đối chiếu chỉ dùng nội bộ, không hiển thị top 1/2/3.

Đây là chức năng thử nghiệm: Qwen VL chưa được kiểm định là bộ nhận diện VSL chuyên dụng. Thiếu mẫu TRAIN hoặc bị Qwen từ chối thì chưa chốt. Bật đối chiếu có thể giảm số kết quả được nhận và tăng độ trễ; chưa có bằng chứng accuracy webcam tăng. Có thể tắt **Đối chiếu ảnh bằng LM Studio** để dùng kết quả Colab theo ngưỡng gốc.

Lượt thử ảnh thực tế đã thành công với `qwen2.5-vl-7b-instruct`: khoảng **13,4 giây**, Qwen trả về chưa chắc chắn. Đây là độ trễ đối chiếu, không phải độ trễ landmark. Worker ảnh không chặn vòng dò tay, timeout 45 giây. Khi LM tắt hoặc thiếu mẫu, ứng dụng báo chưa đối chiếu được và không tạo kết quả giả.

Endpoint `/v1/compose` vẫn hỗ trợ ngắt câu với kiểm tra không thay từ/thứ tự/phủ định. Luồng camera chính dùng LM để **đối chiếu ảnh**. TTS tiếng Việt của thiết bị đọc kết quả.

## Tốc độ và OpenCV

- Preview độc lập với suy luận. Web gửi tối đa khoảng 20 khung/giây, lấy timestamp trước khi encode JPEG. Native dùng image stream của thiết bị.
- WebSocket v2 gửi `frame_received` ngay sau nhận/kiểm tra header. Một khung đang xử lý và tối đa một khung mới đang chờ; khung mới thay khung chờ cũ. Kết quả cũ không mở khóa nhầm gói mới.
- Định vị mặt và phân loại chuỗi chạy ở worker riêng. Adapter detector lấy từ bản desktop, có giới hạn tìm lại tay mỗi khung; feature/classifier vẫn ghim theo Colab.
- OpenCV giải mã JPEG/YUV420/BGRA, xoay, resize, đổi màu; LK optical flow bám texture, hướng dẫn detector tìm lại vùng mất dấu. Không tạo landmark giả. Hull/ROI vẽ vùng tay; đo sáng/nhòe chỉ đưa cảnh báo.
- **Hiện phân tích OpenCV** chỉ bật/tắt lớp vẽ; xử lý OpenCV vẫn hoạt động.

Trên cùng **80 khung hình** từ các đoạn một/hai tay của bản quay màn hình 17/10: median **128,5 → 89,2 ms**, p90 **277,8 → 129,6 ms**; khung dò được hai tay **14 → 17**. Video có overlay sẵn và không có nhãn từng khung đã xác minh: đây chỉ là kiểm tra hiệu năng/tracking, không phải accuracy hay FPS webcam.

Burst socket thật: nhận đủ ACK cho 40 khung, xử lý 2, bỏ 38 khung chờ cũ, kết quả cuối sequence 39.

## Model và cấu hình

Model hiện có **144 từ đã train**, không phải số nhãn chỉ mới chọn trên Colab. Service kiểm tra SHA256/schema. Khi train mới, thay cả bộ file cùng lần xuất rồi khởi động lại. Feature/classifier trong `ai_service/model_runtime.py` giữ hash ở `runtime_provenance.json`; adapter detector riêng ở `realtime_detector.py`. Không lấy cách trộn điểm chưa có validation trong camera sửa tay thay classifier.

| Biến môi trường | Ý nghĩa |
| --- | --- |
| `SIGNVOICE_MODEL_DIR` | Thư mục bộ model, mặc định thư mục cha dự án |
| `LM_STUDIO_URL` | Mặc định `http://127.0.0.1:1234/v1` |
| `LM_STUDIO_VISION_MODEL` | Mặc định `qwen2.5-vl-7b-instruct` |
| `LM_STUDIO_MODEL` | Model chat cho endpoint ngắt câu |
| `LM_STUDIO_API_KEY` | Khóa nếu LM bật xác thực; chỉ đặt ở service |
| `AI_ALLOWED_ORIGINS` | Các origin app được phép kết nối |
| `AI_SERVICE_TOKEN` | Khóa tùy chọn cho triển khai cá nhân |

ZIP `SignVoice_Dataset_ToanBo_MoRong_2026-10-16.zip` cần ở thư mục model để đọc ảnh TRAIN tham chiếu. Service chỉ đọc clip cần dùng, không giải nén cả ZIP 46 GB. Ảnh camera giữ ngắn trong RAM, không ghi vào TRAIN. Dataset/model gốc không thay trong lần tối ưu camera.

## Điện thoại và camera trước/sau

- Camera trước chỉ lật preview; pixel suy luận không lật. Android v8 xử lý YUV420/stride/góc sensor-device tại thiết bị, đo MediaPipe GPU/CPU và gửi JPEG + XYZ cùng khung; có đường YUV service CPU dự phòng. iOS gửi BGRA; web v8 đo tay trước bước nén JPEG.
- Native máy thật: cùng mạng, chạy `powershell -File scripts/start-ai-service.ps1 -ListenHost 0.0.0.0`, nhập `http://IP-MAY-TINH:8001` trong cài đặt camera. Android emulator dùng `10.0.2.2`. Cho phép cổng trên mạng riêng nếu firewall chặn.
- Web điện thoại cần HTTPS cho cả app và AI/WSS. HTTP LAN thông thường không được cấp camera. Dùng reverse proxy HTTPS hoặc `-SslCert`/`-SslKey` với chứng chỉ thiết bị tin cậy. Khai báo origin app trong `AI_ALLOWED_ORIGINS`; backend phục vụ web cần CSP cho phép origin AI.
- Chưa kiểm thử camera trước/sau và tiếng đọc trên điện thoại vật lý. Đã chuẩn bị Android SDK và kiểm tra build Android v8; chưa build iOS. Chi tiết build và giới hạn đo thực tế tại [báo cáo v8](CAMERA_LANDMARK_V8_20261019.md).

## Kiểm chứng

- Flutter: **104 tests** qua, Dart phần camera/microphone sạch, JavaScript web build ở `build/ai-web`; chưa publish.
- Python: **16 tests** qua: pixels/stride/rotation, OpenCV, hàng chờ mới nhất, nhãn đúng chế độ, nguồn TRAIN, worker ảnh, chống kết quả cũ và chống hủy lặp review chậm.
- Replay socket thật giữ timestamp, từ chối gói đảo thứ tự, tách phiên mới, có vùng tay và optical flow.
- Báo cáo ở `ai_service/reports/camera_20261017/`: `latency_comparison.json`, `backpressure_smoke.json`, `vision_smoke.json`. Tổng hợp ở `ai_service/integration_verification.json`.

```powershell
ai_service\.venv\Scripts\python -m unittest discover -s ai_service -p "test_*.py"
ai_service\.venv\Scripts\python -m ai_service.smoke_stream
ai_service\.venv\Scripts\python -m ai_service.smoke_backpressure
flutter test
```

Model vẫn nhận diện từ vựng đã train. Tối ưu camera và thêm VLM không thay dữ liệu TRAIN đa dạng và không biến model hiện tại thành bộ dịch câu ký hiệu liên tục đã kiểm định.

Tham khảo: [camera](https://pub.dev/packages/camera), [flutter_tts](https://pub.dev/packages/flutter_tts), [LM Studio structured output](https://lmstudio.ai/docs/developer/openai-compat/structured-output).
