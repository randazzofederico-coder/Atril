from PIL import Image
import sys
import os

def crop_transparency(input_path, output_path):
    try:
        img = Image.open(input_path)
        img = img.convert("RGBA")
        
        # Get the alpha band
        alpha = img.split()[-1]
        
        # Create a binary mask where alpha > threshold
        threshold = 10
        mask = alpha.point(lambda p: 255 if p > threshold else 0)
        
        # Get the bounding box of the mask
        bbox = mask.getbbox()
        
        if bbox:
            print(f"Original size: {img.size}")
            print(f"Threshold Bounding box: {bbox}")
            
            if bbox != (0, 0, img.width, img.height):
                 cropped_img = img.crop(bbox)
                 print(f"New size: {cropped_img.size}")
                 cropped_img.save(output_path)
                 print(f"Saved cropped image to {output_path}")
            else:
                 print("Image content extends to edges. Forcing a crop to zoom in.")
                 # Crop 15% from each side to "zoom in" the center content.
                 width, height = img.size
                 left = width * 0.15
                 top = height * 0.15
                 right = width * 0.85
                 bottom = height * 0.85
                 
                 cropped_img = img.crop((left, top, right, bottom))
                 # Resize back to original? Not strictly necessary for adaptive icons as valid input, 
                 # but good practice to keep it high res? No, we just save the crop.
                 
                 print(f"New size: {cropped_img.size}")
                 cropped_img.save(output_path)
                 print(f"Saved zoomed cropped image to {output_path}")
                 
        else:
            print("Image is fully transparent!")
            
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    crop_transparency('Atril.png', 'Atril_cropped.png')
