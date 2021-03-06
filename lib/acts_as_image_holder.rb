#
# The main module of the plugin
#
# Copyright (C) by Nikolay V. Nemshilov aka St.
#
module ActsAsImageHolder
  VERSION = "0.8.0"
  
  #
  # The method for the users
  #
  def acts_as_image_holder(options={ })
    options = Options.new(options)
    
    #
    # define validators
    #
    validates_each options.images.collect(&:field) do |record, attr, value|
      record.instance_eval do 
        if @__acts_as_image_holder_problems and !@__acts_as_image_holder_problems.blank?
          self.errors.add attr, (defined?(I18n) ? :is_not_an_image : "is not an image") if @__acts_as_image_holder_problems[attr] == :not_an_image
          self.errors.add attr, (defined?(I18n) ? :has_wrong_type : "has wrong type")   if @__acts_as_image_holder_problems[attr] == :wrong_type
        
        elsif options.images.find{ |i| i.field == attr }.required and self[attr].blank?
          self.errors.add attr, (defined?(I18n) ? :is_required : "is required")
        end
      end
    end
    
    #
    # define the image files setting handling
    #
    options.images.each do |image|
      define_method "#{image.field}=" do |file|
        @__acts_as_image_holder_problems ||= { }
        @__acts_as_image_holder_filedata ||= { }
        @__acts_as_image_holder_thumbsdata ||= { }
        
        return if file.blank?
        
        begin
          # reading and converting the file
          filedata = ImageProc.prepare_data(file, image)
          origdata = ImageProc.to_blob(file) if image.original
          thumbs = image.thumbs.collect{ |thumb| [thumb, ImageProc.prepare_data(file, thumb)] }
          
          # check if the file has a right type
          if image.allowed_type? ImageProc.get_type(file)
            if options.directory
              # save the data for the future file-writting
              @__acts_as_image_holder_filedata[image.field] = filedata
              @__acts_as_image_holder_filedata[image.original] = origdata if origdata
              thumbs.each do |thumb|
                @__acts_as_image_holder_thumbsdata[thumb[0].field]  = thumb[1]
              end
              
              # presetting the filenames for the future files
              self[image.field] = FileProc.guess_file_name(options, file, image)
              self[image.original] = FileProc.guess_original_file_name(options, file) if origdata
              image.thumbs.each do |thumb, i|
                self[thumb.field] = FileProc.guess_thumb_file_name(options, file, thumb, i)
              end
              
            else
              # blobs direct assignment
              self[image.field] = filedata
              self[image.original] = origdata
              thumbs.each do |thumb|
                self[thumb[0].field] = thumb[1]
              end
            end
            
            self[image.type_field] = "#{ImageProc.get_type(filedata)}" if image.type_field
            
          else
            @__acts_as_image_holder_problems[image.field] = :wrong_type
          end
          
        rescue Magick::ImageMagickError
          @__acts_as_image_holder_problems[image.field] = :not_an_image
        end
      end
    end
    
    #
    # defining file-based version additional features
    #
    if options.directory
      # assigning a constant to keep it trackable outside of the code
      const_set 'FILES_DIRECTORY', options.directory
      
      #
      # file url locations getters
      #
      options.images.each do |image|
        define_method "#{image.field}_url" do 
          __file_url_for self[image.field] unless self[image.field].blank?
        end
        
        if image.original
          define_method "#{image.original}_url" do 
            __file_url_for self[image.original] unless self[image.original].blank?
          end
        end
        
        image.thumbs.each do |thumb|
          define_method "#{thumb.field}_url" do 
            __file_url_for self[thumb.field] unless self[thumb.field].blank?
          end
        end
      end
      
      # common file-urls compiler
      define_method "__file_url_for" do |relative_filename|
        full_filename = "#{options.directory}/#{relative_filename}"
        public_dir = "#{RAILS_ROOT}/public"
        
        full_filename[public_dir.size, full_filename.size]
      end
      
      
      #
      # define files handling callbacks
      #
      after_save :acts_as_image_holder_write_files
      after_destroy :acts_as_image_holder_remove_files
      
      # writting down the files
      define_method :acts_as_image_holder_write_files do 
        [@__acts_as_image_holder_filedata || {}, @__acts_as_image_holder_thumbsdata || {}].each do |data_collection|
          data_collection.each do |field_name, filedata|
            FileProc.write_file(options, self[field_name], filedata)
          end
        end
      end
      
      # removing related files after the record is deleted
      define_method :acts_as_image_holder_remove_files do 
        options.images.each do |image|
          FileProc.remove_file(options, self[image.field])
          FileProc.remove_file(options, self[image.original]) if image.original
          image.thumbs.each do |thumb|
            FileProc.remove_file(options, self[thumb.field])
          end
        end
      end
    end
    
    #
    # Some additional useful images handling methods
    #
    module_eval <<-"end_eval"
      #
      # Resize a file and a blob-string
      #
      # @param file - File object or a string file-path
      # @param size - [width, height] array or a "widthxheight" string
      # @param format - "gif", "jpeg", "png", or nil to keep the same
      # @param quality - jpeg - quality 0 - 100, nil to keep the same
      #
      def resize_file(file, size, format=nil, quality=nil)
        file = File.open(file) if file.is_a? String
        ActsAsImageHolder::ImageProc.resize(file, size, format, quality)
      end
      
      def resize_blob(blob, size, format=nil, quality=nil)
        ActsAsImageHolder::ImageProc.resize(blob, size, format, quality)
      end
      
      #
      # Puts a watermark on the given image with the given options
      #
      def watermark_file(file, options)
        ActsAsImageHolder::ImageProc.watermark(file, options)
      end
      
      def watermark_blob(blob, options)
        ActsAsImageHolder::ImageProc.watermark_blob(blob, options)
      end
    end_eval
  end 
end
