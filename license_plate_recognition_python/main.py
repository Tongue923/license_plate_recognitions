from flask import Flask, request, jsonify
import cv2
import numpy as np
from ultralytics import YOLO
from sort.sort import Sort
from fast_plate_ocr import ONNXPlateRecognizer
from util import get_car
import base64
import traceback
from flask_cors import CORS
from skimage.metrics import peak_signal_noise_ratio as psnr
from skimage.metrics import structural_similarity as ssim
import base64  
from werkzeug.utils import secure_filename  
import traceback
import gc
import time
from apscheduler.schedulers.background import BackgroundScheduler
import datetime
from fast_plate_ocr import ONNXPlateRecognizer


# Initialize Flask app
app = Flask(__name__)
gc.collect()

m = ONNXPlateRecognizer('global-plates-mobile-vit-v2-model')  # Ensure this directory exists and contains the model

# Helper function to draw border
def draw_border(img, top_left, bottom_right, color=(0, 255, 0), thickness=10, line_length_x=200, line_length_y=200):
    

    
    x1, y1 = top_left
    x2, y2 = bottom_right

    cv2.line(img, (x1, y1), (x1, y1 + line_length_y), color, thickness)  #-- top-left
    cv2.line(img, (x1, y1), (x1 + line_length_x, y1), color, thickness)

    cv2.line(img, (x1, y2), (x1, y2 - line_length_y), color, thickness)  #-- bottom-left
    cv2.line(img, (x1, y2), (x1 + line_length_x, y2), color, thickness)

    cv2.line(img, (x2, y1), (x2 - line_length_x, y1), color, thickness)  #-- top-right
    cv2.line(img, (x2, y1), (x2, y1 + line_length_y), color, thickness)

    cv2.line(img, (x2, y2), (x2, y2 - line_length_y), color, thickness)  #-- bottom-right
    cv2.line(img, (x2, y2), (x2 - line_length_x, y2), color, thickness)

    return img

# Image processing function
def process_image(frame):

    """
    Process the image to detect vehicles, license plates, and recognize text.

    Args:
        frame (numpy.ndarray): Input image in BGR format.

    Returns:
        dict: Processed image as Base64 and recognized texts for all detected license plates.
    """
    #ocr = PaddleOCR(lang='en')
    results = {}
    coco_model = YOLO('yolov8n.pt')  # Path to YOLOv8 COCO model
    license_plate_detector = YOLO('license_plate_detector.pt')  # Path to License Plate Detection model
    mot_tracker = Sort()  # Vehicle tracking object
    recognized_texts = []  # Initialize an empty list to store recognized texts
    try:
        # Encode the original image to Base64
        _, original_buffer = cv2.imencode('.jpg', frame)
        original_img_base64 = base64.b64encode(original_buffer).decode('utf-8')

        # Detect vehicles using YOLO COCO model
        detections = coco_model(frame)[0]
        detections_ = []
        vehicles = [2, 3, 5, 7]  # Vehicle class IDs for car, bus, truck, motorcycle
        for detection in detections.boxes.data.tolist():
            x1, y1, x2, y2, score, class_id = detection
            if int(class_id) in vehicles:
                detections_.append([x1, y1, x2, y2, score])

        # Check if there are valid detections before updating the tracker
        if len(detections_) > 0:
            # Update SORT tracker
            track_ids = mot_tracker.update(np.asarray(detections_))
        else:
            track_ids = []  # No detections, no tracking

        # Detect license plates using the license plate model
        license_plates = license_plate_detector(frame)[0]
        time.sleep(1)

        # Loop through all detected license plates and process each one
        for license_plate in license_plates.boxes.data.tolist():
            x1, y1, x2, y2, score, class_id = license_plate 

            # Assign license plate to a car
            xcar1, ycar1, xcar2, ycar2, car_id = get_car(license_plate, track_ids)
            
            time.sleep(1)
            if car_id != -1:
                # Crop license plate with boundary checks
                x1_crop = max(int(x1), 0)
                y1_crop = max(int(y1), 0)
                x2_crop = min(int(x2), frame.shape[1] - 1)
                y2_crop = min(int(y2), frame.shape[0] - 1)
                print(f"\n[{datetime.datetime.now()}] x1: {x1_crop}, y1: {y1_crop}, x2: {x2_crop}, y2: {y2_crop}")
                license_plate_crop = frame[int(y1):int(y2), int(x1):int(x2), 1]
                cv2.imwrite('./testing.jpg', license_plate_crop)
                # OCR Recognition
                print(f'\n[{datetime.datetime.now()}] Test recognizing started...')

                result = m.run('./testing.jpg')

                print(f"\n[{datetime.datetime.now()}] Success!!! ")   
                cleaned_result = [''.join(char for char in item if char.isalnum()) for item in result]
                print(f"\n[{datetime.datetime.now()}] Result = {cleaned_result}")

                
                if result:  
                    #text = result[0][0][0].replace(' ', '')
                    
                    text = cleaned_result[0] if cleaned_result else "No Text"

                    recognized_texts.append(str(text))  # Append the recognized text for each car
                    frame[int(y1 - (y2 - y1)/2) : int(y1), int(x1) : int (x2), :] = (255, 255, 255)
                    white_frame_height = int(y1) - int(y1 - (y2 - y1) / 2)
                    white_frame_width = int(x2) - int(x1)

                    # Dynamically calculate font size to fit the white frame
                    font = cv2.FONT_HERSHEY_SIMPLEX
                    font_scale = 1
                    thickness = 1

                    while True:
                        (text_width, text_height), baseline = cv2.getTextSize(text, font, font_scale, thickness)
                        if text_width <= white_frame_width and text_height <= white_frame_height:
                            break
                        font_scale -= 0.1  # Reduce font size if it doesn't fit

                    # Center the text inside the white frame
                    text_x = int(x1 + (white_frame_width - text_width) / 2)
                    text_y = int(y1 - (y2 - y1) / 2 + (white_frame_height + text_height) / 2)
                    draw_border(frame, (int(x1), int(y1)), (int(x2), int(y2)), (0, 255, 0), 3,
                                                line_length_x= 10, line_length_y=10)
                    # Add the text to the frame
                    cv2.putText(frame, text, (text_x, text_y), font, font_scale, (0, 0, 0), thickness)

                
        # If no valid detections or text found, add a default message for each license plate
        if not recognized_texts:
            recognized_texts.append("No license plate or text found")

        # Encode the processed image to Base64
        _, buffer = cv2.imencode('.jpg', frame)
        img_base64 = base64.b64encode(buffer).decode('utf-8')

        return {
             # List of recognized texts for all cars
            'processed_image_base64': img_base64,
            'recognized_text': recognized_texts
        }

    except Exception as e:
        print(f"Error processing the image: {e}")
        return {
            'recognized_text': ["No license plate or text found"],  # Default error message
            'processed_image_base64': original_img_base64  # Return original image base64 if an error occurs
            
        }


# Flask route to handle image upload and processing
@app.route('/process-image', methods=['POST'])
def upload_image():
    try:
        if not request:
            frame = cv2.read('./sample3.jpg')

        # Validate request content
        if 'file' not in request.files:
            return jsonify({'error': 'No file part in the request.'}), 400

        file = request.files['file']
        if file.filename == '':
            return jsonify({'error': 'No file selected for uploading.'}), 400
        # Read the image in memory
        file_stream = file.read()
        np_arr = np.frombuffer(file_stream, np.uint8)
        frame = cv2.imdecode(np_arr, cv2.IMREAD_COLOR)

        if frame is None:
            return jsonify({'error': 'Invalid image file.'}), 400
        #Process the image
        try:

            # Request handling code...
            result = process_image(frame)
            print(f"\n[{datetime.datetime.now()}] Image processed successfully: {result['recognized_text']}")
            
            
            return jsonify(result), 200
        except Exception as e:
            print(f"Error processing the image: {str(e)}")  
            return jsonify({'error': 'An error occurred during image processing.', 'details': str(e)}), 500

    except Exception as e:
        # Log the exception stack trace for debugging
        traceback.print_exc()
        return jsonify({'error': 'An error occurred during image processing.', 'details': str(e)}), 500

def sensor():
    
    print(f"\n[{datetime.datetime.now()}] Checking")
    check = cv2.imread('./sample4.jpg')
    result = process_image(check)
    if result['recognized_text']==["No license plate or text found"]:
        print(f"\n[{datetime.datetime.now()}] Server will be restarted....")
        app.run(debug=True, host='0.0.0.0', port=5000)
        CORS(app)
        
    print(f"\n[{datetime.datetime.now()}] Do not have any problem on this server...")


sched = BackgroundScheduler(daemon=True)
sched.add_job(sensor,'interval', minutes = 5 )
sched.start()

# Run the Flask app
if __name__ == '__main__':
    
    """ Function for test purposes. """
    # Ensure debug is False in production
    app.run(debug=True, host='0.0.0.0', port=5000)
    CORS(app)


